//! OpenAI-compatible HTTP client (Ollama, vLLM, OpenAI, etc.).

use super::traits::LocalInferenceEngine;
use super::{ChatMessage, PortableFallbackRuntime};
use anyhow::{Context, Result};
use futures_util::StreamExt;
use serde::{Deserialize, Serialize};
use std::time::Duration;

pub const DEFAULT_BASE_URL: &str = "http://127.0.0.1:11434/v1";
pub const DEFAULT_MODEL: &str = "llama3.2";

#[derive(Debug, Clone)]
pub struct AiSettings {
    pub base_url: String,
    pub api_key: Option<String>,
    pub model: String,
    pub onnx_model_path: Option<String>,
}

impl AiSettings {
    pub fn from_map(values: &std::collections::HashMap<String, String>) -> Self {
        let base_url = values
            .get("ai.baseUrl")
            .map(|s| s.trim().to_string())
            .filter(|s| !s.is_empty())
            .unwrap_or_else(|| DEFAULT_BASE_URL.to_string());
        let api_key = values
            .get("ai.apiKey")
            .map(|s| s.trim().to_string())
            .filter(|s| !s.is_empty());
        let model = values
            .get("ai.model")
            .map(|s| s.trim().to_string())
            .filter(|s| !s.is_empty())
            .unwrap_or_else(|| DEFAULT_MODEL.to_string());
        let onnx_model_path = values.get("ai.onnxModelPath").cloned();
        Self {
            base_url,
            api_key,
            model,
            onnx_model_path,
        }
    }

    pub fn endpoint_configured(&self) -> bool {
        !self.base_url.trim().is_empty()
    }

    fn client(&self) -> Result<reqwest::Client> {
        reqwest::Client::builder()
            .user_agent("CollegeDesktop/0.1 (+https://college.app)")
            .timeout(Duration::from_secs(60))
            .build()
            .context("build HTTP client")
    }

    fn auth(&self, req: reqwest::RequestBuilder) -> reqwest::RequestBuilder {
        if let Some(key) = &self.api_key {
            req.bearer_auth(key)
        } else {
            req
        }
    }

    fn url(&self, path: &str) -> String {
        let base = self.base_url.trim_end_matches('/');
        format!("{base}{path}")
    }
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PingResult {
    pub ok: bool,
    pub message: String,
    pub model: Option<String>,
}

pub async fn ping(settings: &AiSettings) -> PingResult {
    if !settings.endpoint_configured() {
        return PingResult {
            ok: false,
            message: "No AI base URL configured.".into(),
            model: None,
        };
    }

    let client = match settings.client() {
        Ok(c) => c,
        Err(e) => {
            return PingResult {
                ok: false,
                message: e.to_string(),
                model: None,
            };
        }
    };

    let url = settings.url("/models");
    let response = match settings
        .auth(client.get(&url))
        .send()
        .await
    {
        Ok(r) => r,
        Err(e) => {
            let is_ollama = settings.base_url.contains("11434") || settings.base_url.contains("ollama");
            let message = if is_ollama {
                format!(
                    "Ollama not reachable at {} — is `ollama serve` running? ({e})",
                    settings.base_url.trim_end_matches('/')
                )
            } else {
                format!("Cannot reach {url}: {e}")
            };
            return PingResult {
                ok: false,
                message,
                model: Some(settings.model.clone()),
            };
        }
    };

    if !response.status().is_success() {
        return PingResult {
            ok: false,
            message: format!("HTTP {} from {url}", response.status()),
            model: Some(settings.model.clone()),
        };
    }

    let is_ollama = settings.base_url.contains("11434") || settings.base_url.contains("ollama");
    let message = if is_ollama {
        format!(
            "Ollama is running at {} (model: {})",
            settings.base_url.trim_end_matches('/'),
            settings.model
        )
    } else {
        format!(
            "Connected to {} (model: {})",
            settings.base_url.trim_end_matches('/'),
            settings.model
        )
    };

    PingResult {
        ok: true,
        message,
        model: Some(settings.model.clone()),
    }
}

#[derive(Serialize)]
struct ChatRequest<'a> {
    model: &'a str,
    messages: &'a [ChatMessage],
    stream: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    max_tokens: Option<u32>,
}

#[derive(Deserialize)]
struct ChatResponse {
    choices: Vec<ChatChoice>,
}

#[derive(Deserialize)]
struct ChatChoice {
    message: ChatChoiceMessage,
}

#[derive(Deserialize)]
struct ChatChoiceMessage {
    content: String,
}

#[derive(Deserialize)]
struct StreamChunk {
    choices: Vec<StreamChoice>,
}

#[derive(Deserialize)]
struct StreamChoice {
    delta: StreamDelta,
}

#[derive(Deserialize)]
struct StreamDelta {
    content: Option<String>,
}

pub fn chunk_text(text: &str, chunk_size: usize) -> Vec<String> {
    if chunk_size == 0 {
        return vec![text.to_string()];
    }
    text.chars()
        .collect::<Vec<_>>()
        .chunks(chunk_size)
        .map(|c| c.iter().collect())
        .filter(|s: &String| !s.is_empty())
        .collect()
}

pub async fn chat_completion_stream<F>(
    settings: &AiSettings,
    messages: &[ChatMessage],
    max_tokens: u32,
    mut on_delta: F,
) -> Result<String>
where
    F: FnMut(&str),
{
    let client = settings.client()?;
    let body = ChatRequest {
        model: &settings.model,
        messages,
        stream: true,
        max_tokens: Some(max_tokens),
    };
    let url = settings.url("/chat/completions");
    let response = settings
        .auth(client.post(&url).json(&body))
        .send()
        .await
        .with_context(|| format!("POST {url}"))?;

    if !response.status().is_success() {
        let status = response.status();
        let text = response.text().await.unwrap_or_default();
        anyhow::bail!("HTTP {status} from chat/completions stream: {text}");
    }

    let mut full = String::new();
    let mut buffer = String::new();
    let mut stream = response.bytes_stream();
    while let Some(chunk) = stream.next().await {
        let chunk = chunk.context("read stream chunk")?;
        buffer.push_str(&String::from_utf8_lossy(&chunk));
        while let Some(pos) = buffer.find('\n') {
            let line = buffer[..pos].trim().to_string();
            buffer = buffer[pos + 1..].to_string();
            if line.is_empty() || line.starts_with(':') {
                continue;
            }
            let data = line.strip_prefix("data:").unwrap_or(line.as_str()).trim();
            if data == "[DONE]" {
                continue;
            }
            let parsed: StreamChunk = match serde_json::from_str(data) {
                Ok(v) => v,
                Err(_) => continue,
            };
            if let Some(delta) = parsed
                .choices
                .into_iter()
                .next()
                .and_then(|c| c.delta.content)
                .filter(|s| !s.is_empty())
            {
                full.push_str(&delta);
                on_delta(&delta);
            }
        }
    }
    if full.trim().is_empty() {
        anyhow::bail!("empty streaming chat completion");
    }
    Ok(full)
}

pub async fn chat_completion(
    settings: &AiSettings,
    messages: &[ChatMessage],
    max_tokens: u32,
) -> Result<String> {
    let client = settings.client()?;
    let body = ChatRequest {
        model: &settings.model,
        messages,
        stream: false,
        max_tokens: Some(max_tokens),
    };
    let url = settings.url("/chat/completions");
    let response = settings
        .auth(client.post(&url).json(&body))
        .send()
        .await
        .with_context(|| format!("POST {url}"))?;

    if !response.status().is_success() {
        let status = response.status();
        let text = response.text().await.unwrap_or_default();
        anyhow::bail!("HTTP {status} from chat/completions: {text}");
    }

    let parsed: ChatResponse = response.json().await.context("parse chat response")?;
    parsed
        .choices
        .into_iter()
        .next()
        .map(|c| c.message.content)
        .filter(|c| !c.trim().is_empty())
        .context("empty chat completion")
}

#[derive(Serialize)]
struct EmbedRequest<'a> {
    model: &'a str,
    input: &'a [String],
}

#[derive(Deserialize)]
struct EmbedResponse {
    data: Vec<EmbedData>,
}

#[derive(Deserialize)]
struct EmbedData {
    embedding: Vec<f32>,
}

pub async fn embeddings(settings: &AiSettings, texts: &[String]) -> Result<Vec<Vec<f32>>> {
    if texts.is_empty() {
        return Ok(vec![]);
    }
    let client = settings.client()?;
    let body = EmbedRequest {
        model: &settings.model,
        input: texts,
    };
    let url = settings.url("/embeddings");
    let response = settings
        .auth(client.post(&url).json(&body))
        .send()
        .await
        .with_context(|| format!("POST {url}"))?;

    if !response.status().is_success() {
        let status = response.status();
        let text = response.text().await.unwrap_or_default();
        anyhow::bail!("HTTP {status} from embeddings: {text}");
    }

    let parsed: EmbedResponse = response.json().await.context("parse embeddings")?;
    let mut out: Vec<Vec<f32>> = parsed.data.into_iter().map(|d| d.embedding).collect();
    if out.len() != texts.len() {
        anyhow::bail!(
            "embeddings count mismatch: expected {}, got {}",
            texts.len(),
            out.len()
        );
    }
    // Normalize for cosine similarity consistency with hash backend.
    for vec in &mut out {
        let norm = vec.iter().map(|v| v * v).sum::<f32>().sqrt().max(1e-8);
        for v in vec {
            *v /= norm;
        }
    }
    Ok(out)
}

/// Hash-stub chat used when the remote endpoint is unreachable.
pub fn hash_stub_chat(messages: &[ChatMessage], max_tokens: u32) -> Result<String> {
    PortableFallbackRuntime::new().complete(messages, max_tokens)
}
