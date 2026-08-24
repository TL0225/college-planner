//! Unified AI runtime — OpenAI-compatible remote endpoint with hash-stub fallback.

mod onnx_stub;
pub mod openai_compat;
mod traits;

use crate::db::AppDb;
use crate::paths::AppPaths;
use anyhow::Result;
use onnx_stub::{local_model_ready, onnx_local_embed, onnx_path_configured, resolve_local_model_file};
use openai_compat::{hash_stub_chat, AiSettings, PingResult, DEFAULT_BASE_URL, DEFAULT_MODEL};
use parking_lot::Mutex;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::Arc;
use std::time::{Duration, Instant};
use traits::{LocalInferenceEngine, TextEmbeddingEngine};

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AiRuntimeStatus {
    pub backend: String,
    pub embeddings_backend: String,
    pub embeddings_ready: bool,
    pub llm_ready: bool,
    pub model: String,
    pub endpoint_configured: bool,
    pub onnx_path_configured: bool,
    pub model_dir: String,
    pub device: String,
    /// Configured OpenAI-compatible base URL (Ollama default: http://127.0.0.1:11434/v1).
    pub endpoint_url: String,
    /// True when the endpoint looks like a local Ollama server.
    pub ollama_endpoint: bool,
    /// Result of the most recent ping (Settings → Test connection or status refresh).
    pub ping_ok: Option<bool>,
    /// Human-readable connection detail for Settings / cutover checklist.
    pub ping_message: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ChatMessage {
    pub role: String,
    pub content: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ChatCompletionRequest {
    pub messages: Vec<ChatMessage>,
    pub max_tokens: Option<u32>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ChatCompletionResponse {
    pub content: String,
    pub backend: String,
}

struct HealthCache {
    ok: bool,
    checked_at: Option<Instant>,
}

impl HealthCache {
    fn new() -> Self {
        Self {
            ok: false,
            checked_at: None,
        }
    }

    fn record(&mut self, ok: bool) {
        self.ok = ok;
        self.checked_at = Some(Instant::now());
    }

    fn is_fresh(&self) -> bool {
        self.checked_at
            .map(|t| t.elapsed() < Duration::from_secs(120))
            .unwrap_or(false)
    }
}

pub struct AiRuntime {
    db: Arc<AppDb>,
    fallback: PortableFallbackRuntime,
    model_dir: std::path::PathBuf,
    health: Mutex<HealthCache>,
}

impl AiRuntime {
    pub fn new(paths: Arc<AppPaths>, db: Arc<AppDb>) -> Result<Self> {
        std::fs::create_dir_all(&paths.models_dir)?;
        tracing::info!(
            path = %paths.models_dir.display(),
            "AI runtime initialized (OpenAI-compatible primary, hash-stub fallback)"
        );
        Ok(Self {
            db,
            fallback: PortableFallbackRuntime::new(),
            model_dir: paths.models_dir.clone(),
            health: Mutex::new(HealthCache::new()),
        })
    }

    fn load_settings_map(&self) -> Result<HashMap<String, String>> {
        self.db.with_conn(|conn| {
            let mut stmt = conn.prepare("SELECT key, value FROM app_settings")?;
            let rows = stmt
                .query_map([], |r| Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?)))?
                .collect::<Result<HashMap<_, _>, _>>()?;
            Ok(rows)
        })
    }

    fn settings(&self) -> Result<AiSettings> {
        Ok(AiSettings::from_map(&self.load_settings_map()?))
    }

    pub fn status(&self) -> AiRuntimeStatus {
        let settings = self.settings().unwrap_or_else(|_| AiSettings {
            base_url: DEFAULT_BASE_URL.into(),
            api_key: None,
            model: DEFAULT_MODEL.into(),
            onnx_model_path: None,
        });
        let endpoint_url = settings.base_url.trim().to_string();
        let endpoint_configured = settings.endpoint_configured();
        let ollama_endpoint = endpoint_url.contains("11434")
            || endpoint_url.contains("ollama")
            || endpoint_url.eq_ignore_ascii_case(DEFAULT_BASE_URL);
        let health = self.health.lock();
        let health_fresh = health.is_fresh();
        let health_ok = health_fresh && health.ok;
        let ping_ok = if health_fresh {
            Some(health.ok)
        } else {
            None
        };
        let ping_message = if !endpoint_configured {
            "No AI base URL configured — using hash-stub fallback.".into()
        } else if health_fresh {
            if health.ok {
                if ollama_endpoint {
                    format!("Ollama reachable at {endpoint_url}")
                } else {
                    format!("OpenAI-compatible endpoint reachable at {endpoint_url}")
                }
            } else if ollama_endpoint {
                format!(
                    "Ollama not responding at {endpoint_url} — start with `ollama serve` or check Settings → Test connection"
                )
            } else {
                format!(
                    "Cannot reach {endpoint_url} — assistant falls back to hash-stub until ping succeeds"
                )
            }
        } else if ollama_endpoint {
            format!(
                "Ollama configured at {endpoint_url} — use Settings → Test connection to verify"
            )
        } else {
            format!(
                "Endpoint configured at {endpoint_url} — use Settings → Test connection to verify"
            )
        };
        let local_ready = local_model_ready(settings.onnx_model_path.as_deref(), &self.model_dir);
        let llm_ready = health_ok || endpoint_configured || local_ready;
        let embeddings_ready = llm_ready;
        let backend = if endpoint_configured {
            "openai-compat".into()
        } else if local_ready {
            "onnx-local".into()
        } else {
            "hash-stub".into()
        };
        let embeddings_backend = if endpoint_configured {
            "openai-compat".into()
        } else if local_ready {
            "onnx-local".into()
        } else {
            "hash".into()
        };
        AiRuntimeStatus {
            backend,
            embeddings_backend,
            embeddings_ready,
            llm_ready,
            model: settings.model,
            endpoint_configured,
            onnx_path_configured: onnx_path_configured(settings.onnx_model_path.as_deref())
                || local_ready,
            model_dir: self.model_dir.display().to_string(),
            device: if endpoint_configured {
                "Remote".into()
            } else {
                "CPU".into()
            },
            endpoint_url,
            ollama_endpoint,
            ping_ok,
            ping_message,
        }
    }

    pub async fn ping(&self) -> Result<PingResult> {
        let settings = self.settings()?;
        let result = openai_compat::ping(&settings).await;
        self.health.lock().record(result.ok);
        Ok(result)
    }

    pub fn embed(&self, texts: &[String]) -> Result<Vec<Vec<f32>>> {
        let settings = self.settings()?;
        if settings.endpoint_configured() {
            match tauri::async_runtime::block_on(openai_compat::embeddings(&settings, texts)) {
                Ok(vecs) => {
                    self.health.lock().record(true);
                    return Ok(vecs);
                }
                Err(e) => {
                    tracing::warn!(error = %e, "OpenAI-compatible embeddings failed; trying local ONNX path");
                    self.health.lock().record(false);
                }
            }
        }
        if let Some(path) =
            resolve_local_model_file(settings.onnx_model_path.as_deref(), &self.model_dir)
        {
            if let Some(vecs) = onnx_local_embed(&path, texts, 384) {
                tracing::debug!(path = %path.display(), "Using onnx-local embeddings");
                return Ok(vecs);
            }
        }
        self.fallback.embed(texts)
    }

    pub async fn chat_async(&self, req: ChatCompletionRequest) -> Result<ChatCompletionResponse> {
        self.chat_stream_async(req, |_| {}).await
    }

    pub async fn chat_stream_async<F>(
        &self,
        req: ChatCompletionRequest,
        mut on_chunk: F,
    ) -> Result<ChatCompletionResponse>
    where
        F: FnMut(&str),
    {
        let settings = self.settings()?;
        let max_tokens = req.max_tokens.unwrap_or(512);

        if settings.endpoint_configured() {
            match openai_compat::chat_completion_stream(
                &settings,
                &req.messages,
                max_tokens,
                &mut on_chunk,
            )
            .await
            {
                Ok(content) => {
                    self.health.lock().record(true);
                    return Ok(ChatCompletionResponse {
                        content,
                        backend: "openai-compat-stream".into(),
                    });
                }
                Err(e) => {
                    tracing::warn!(error = %e, "OpenAI-compatible stream failed; trying non-stream");
                    match openai_compat::chat_completion(&settings, &req.messages, max_tokens).await
                    {
                        Ok(content) => {
                            self.health.lock().record(true);
                            for chunk in openai_compat::chunk_text(&content, 48) {
                                on_chunk(&chunk);
                            }
                            return Ok(ChatCompletionResponse {
                                content,
                                backend: "openai-compat".into(),
                            });
                        }
                        Err(e2) => {
                            tracing::warn!(error = %e2, "OpenAI-compatible chat failed; using hash-stub fallback");
                            self.health.lock().record(false);
                        }
                    }
                }
            }
        }

        let content = hash_stub_chat(&req.messages, max_tokens)?;
        for chunk in openai_compat::chunk_text(&content, 48) {
            on_chunk(&chunk);
        }
        Ok(ChatCompletionResponse {
            content,
            backend: "hash-stub".into(),
        })
    }

    pub fn chat(&self, req: ChatCompletionRequest) -> Result<ChatCompletionResponse> {
        tauri::async_runtime::block_on(self.chat_async(req))
    }
}

/// Deterministic portable embeddings used when the remote endpoint is unreachable.
#[derive(Clone)]
pub struct PortableFallbackRuntime;

impl PortableFallbackRuntime {
    pub fn new() -> Self {
        Self
    }

    pub fn hash_embed(text: &str, dims: usize) -> Vec<f32> {
        use sha2::{Digest, Sha256};
        let mut out = vec![0f32; dims];
        let digest = Sha256::digest(text.as_bytes());
        for (i, slot) in out.iter_mut().enumerate() {
            let b = digest[i % digest.len()] as f32;
            *slot = (b / 255.0) * 2.0 - 1.0;
        }
        let norm = out.iter().map(|v| v * v).sum::<f32>().sqrt().max(1e-8);
        for v in &mut out {
            *v /= norm;
        }
        out
    }
}

impl TextEmbeddingEngine for PortableFallbackRuntime {
    fn is_ready(&self) -> bool {
        true
    }

    fn embed(&self, texts: &[String]) -> Result<Vec<Vec<f32>>> {
        Ok(texts.iter().map(|t| Self::hash_embed(t, 384)).collect())
    }
}

impl LocalInferenceEngine for PortableFallbackRuntime {
    fn is_ready(&self) -> bool {
        true
    }

    fn complete(&self, messages: &[ChatMessage], _max_tokens: u32) -> Result<String> {
        let system = messages
            .iter()
            .find(|m| m.role == "system")
            .map(|m| m.content.as_str())
            .unwrap_or("");
        let last = messages
            .iter()
            .rev()
            .find(|m| m.role == "user")
            .map(|m| m.content.as_str())
            .unwrap_or("");
        let lower = last.to_ascii_lowercase();
        let empty = system.contains("WorkspaceStatus: empty");

        if empty {
            return Ok(
                "Your College workspace is empty (no semesters/courses yet).\n\n\
                 Open Settings → Load sample data, or add courses in College → Planner, then ask again."
                    .into(),
            );
        }

        let mut answer = String::new();
        if !system.is_empty() {
            let snippet: String = system
                .lines()
                .filter(|l| !l.starts_with("WorkspaceStatus:"))
                .take(12)
                .collect::<Vec<_>>()
                .join("\n");
            if lower.contains("credit") || lower.contains("degree") || lower.contains("require") {
                answer.push_str("From your planner:\n");
                answer.push_str(&snippet);
            } else if lower.contains("calendar")
                || lower.contains("deadline")
                || lower.contains("event")
                || lower.contains("task")
            {
                answer.push_str("From your calendar:\n");
                answer.push_str(&snippet);
            } else if lower.contains("job")
                || lower.contains("career")
                || lower.contains("interview")
                || lower.contains("application")
            {
                answer.push_str("From your career tracker:\n");
                answer.push_str(&snippet);
            } else {
                answer.push_str("Workspace snapshot:\n");
                answer.push_str(&snippet);
            }
        } else {
            answer.push_str(&format!("You asked: \"{last}\"."));
        }
        Ok(answer)
    }
}
