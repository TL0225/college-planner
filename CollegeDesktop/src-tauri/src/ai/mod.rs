//! Unified AI runtime — on-device Gemma 4 E4B LLM + bundled embedding models.

mod bundled;
mod local_llm;
mod onnx_stub;
pub mod openai_compat;
mod traits;

pub use bundled::{ensure_models, resource_models_dir, EMBED_DIMS, EMBED_NAME, INSTRUCT_NAME};
pub use local_llm::{LocalLlm, LlmModelStatus, LLM_DISPLAY_NAME, LLM_FILE_NAME};

use crate::db::AppDb;
use crate::paths::AppPaths;
use crate::platform;
use anyhow::Result;
use bundled::ClmModel;
use openai_compat::{AiSettings, PingResult};
use parking_lot::Mutex;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::collections::HashMap;
use std::sync::Arc;
use std::time::{Duration, Instant};
use tauri::AppHandle;
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
    pub endpoint_url: String,
    pub ollama_endpoint: bool,
    pub ping_ok: Option<bool>,
    pub ping_message: String,
    pub llm_installed: bool,
    pub llm_loaded: bool,
    pub llm_downloading: bool,
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
    embed_model: ClmModel,
    model_dir: std::path::PathBuf,
    device: String,
    health: Mutex<HealthCache>,
    fallback: PortableFallbackRuntime,
    pub local_llm: Arc<LocalLlm>,
}

impl AiRuntime {
    pub fn new(paths: Arc<AppPaths>, db: Arc<AppDb>) -> Result<Self> {
        std::fs::create_dir_all(&paths.models_dir)?;
        let resource = resource_models_dir();
        ensure_models(paths.models_dir.as_path(), resource.as_deref())?;
        let embed_model = ClmModel::load(&paths.models_dir.join(EMBED_NAME))?;
        let local_llm = Arc::new(LocalLlm::new(&paths.models_dir));
        local_llm.ensure_from_resources(resource.as_deref())?;
        let device = platform::ai_device_backend().to_string();
        tracing::info!(
            path = %paths.models_dir.display(),
            device = %device,
            llm_installed = local_llm.is_installed(),
            "AI runtime initialized (Gemma 4 E4B + bundled embeddings)"
        );
        Ok(Self {
            db,
            embed_model,
            model_dir: paths.models_dir.clone(),
            device,
            health: Mutex::new(HealthCache::new()),
            fallback: PortableFallbackRuntime::new(),
            local_llm,
        })
    }

    pub fn llm_status(&self) -> LlmModelStatus {
        self.local_llm.status()
    }

    pub async fn ensure_llm_download(&self, app: AppHandle) -> Result<()> {
        self.local_llm.download_if_needed(app).await
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
        let llm_installed = self.local_llm.is_installed();
        let llm_loaded = self.local_llm.is_loaded();
        let llm_downloading = self.local_llm.is_downloading();
        let backend = format!("local-{}", self.device);
        let health = self.health.lock();
        let health_fresh = health.is_fresh();
        let llm_ready = llm_loaded || llm_installed;

        let ping_message = if llm_loaded {
            format!("{LLM_DISPLAY_NAME} loaded on {} (offline)", self.device)
        } else if llm_downloading {
            format!("Downloading {LLM_DISPLAY_NAME}…")
        } else if llm_installed {
            format!("{LLM_DISPLAY_NAME} installed — loads on first chat")
        } else {
            format!("{LLM_DISPLAY_NAME} not installed — download from Settings → Assistant")
        };

        AiRuntimeStatus {
            backend: backend.clone(),
            embeddings_backend: format!("bundled-{}", EMBED_NAME),
            embeddings_ready: true,
            llm_ready,
            model: if llm_installed {
                LLM_DISPLAY_NAME.into()
            } else {
                LLM_DISPLAY_NAME.into()
            },
            endpoint_configured: false,
            onnx_path_configured: llm_installed,
            model_dir: self.model_dir.display().to_string(),
            device: self.device.clone(),
            endpoint_url: String::new(),
            ollama_endpoint: false,
            ping_ok: if health_fresh {
                Some(health.ok)
            } else {
                Some(llm_installed)
            },
            ping_message,
            llm_installed,
            llm_loaded,
            llm_downloading,
        }
    }

    pub async fn ping(&self) -> Result<PingResult> {
        let llm_installed = self.local_llm.is_installed();
        let embed_ok = self.model_dir.join(EMBED_NAME).is_file();
        let ok = embed_ok && llm_installed;
        self.health.lock().record(ok);
        Ok(PingResult {
            ok,
            message: if llm_installed {
                format!("{LLM_DISPLAY_NAME} ready ({})", self.device)
            } else if embed_ok {
                format!("Embeddings ready — {LLM_DISPLAY_NAME} needs download (~4.3 GB)")
            } else {
                "AI models missing — reinstall the app".into()
            },
            model: Some(LLM_DISPLAY_NAME.into()),
        })
    }

    fn cached_embed(&self, texts: &[String]) -> Result<Vec<Vec<f32>>> {
        let mut out = Vec::with_capacity(texts.len());
        for text in texts {
            let mut hasher = Sha256::new();
            hasher.update(EMBED_NAME.as_bytes());
            hasher.update(text.as_bytes());
            let hash = hex::encode(hasher.finalize());
            let cached: Option<String> = self.db.with_conn(|conn| {
                use rusqlite::OptionalExtension;
                conn.query_row(
                    "SELECT vector_json FROM ai_embed_cache WHERE content_hash = ?1 AND model_tag = ?2",
                    rusqlite::params![hash, EMBED_NAME],
                    |r| r.get(0),
                )
                .optional()
                .map_err(Into::into)
            })?;
            if let Some(json) = cached {
                if let Ok(v) = serde_json::from_str::<Vec<f32>>(&json) {
                    out.push(v);
                    continue;
                }
            }
            let vec = self
                .embed_model
                .embed_texts(std::slice::from_ref(text))
                .into_iter()
                .next()
                .unwrap_or_else(|| PortableFallbackRuntime::hash_embed(text, EMBED_DIMS));
            let json = serde_json::to_string(&vec)?;
            let now = chrono::Utc::now().to_rfc3339();
            let _ = self.db.with_conn(|conn| {
                conn.execute(
                    "INSERT INTO ai_embed_cache (content_hash, model_tag, dims, vector_json, updated_at)
                     VALUES (?1, ?2, ?3, ?4, ?5)
                     ON CONFLICT(content_hash) DO UPDATE SET
                       vector_json = excluded.vector_json,
                       updated_at = excluded.updated_at,
                       dims = excluded.dims,
                       model_tag = excluded.model_tag",
                    rusqlite::params![hash, EMBED_NAME, EMBED_DIMS as i64, json, now],
                )?;
                Ok(())
            });
            out.push(vec);
        }
        Ok(out)
    }

    pub fn embed(&self, texts: &[String]) -> Result<Vec<Vec<f32>>> {
        match self.cached_embed(texts) {
            Ok(v) => Ok(v),
            Err(e) => {
                tracing::warn!(error = %e, "embed cache path failed; using model directly");
                Ok(self.embed_model.embed_texts(texts))
            }
        }
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
        F: FnMut(&str) + Send + 'static,
    {
        let max_tokens = req.max_tokens.unwrap_or(768);
        let fallback = self.fallback.clone();
        let device = self.device.clone();
        let on_chunk = Arc::new(Mutex::new(on_chunk));

        if self.local_llm.is_installed() && self.local_llm.is_server_installed() {
            let on_chunk_cb = Arc::clone(&on_chunk);
            let result = self
                .local_llm
                .chat_stream(
                    &req.messages,
                    max_tokens,
                    move |piece| {
                        on_chunk_cb.lock()(piece);
                    },
                )
                .await;

            match result {
                Ok(content) if !content.trim().is_empty() => {
                    self.health.lock().record(true);
                    return Ok(ChatCompletionResponse {
                        content,
                        backend: format!("local-llm-{device}"),
                    });
                }
                Ok(content) => {
                    tracing::warn!("LLM returned empty response; using fallback");
                    let fb = fallback.complete(&req.messages, max_tokens)?;
                    self.health.lock().record(true);
                    return Ok(ChatCompletionResponse {
                        content: if content.is_empty() { fb } else { content },
                        backend: format!("local-llm-fallback-{device}"),
                    });
                }
                Err(e) => {
                    tracing::warn!(error = %e, "LLM inference failed; using fallback");
                }
            }
        }

        // No LLM installed or inference failed.
        let content = if !self.local_llm.is_installed() || !self.local_llm.is_server_installed() {
            format!(
                "I'd love to help with that, but {LLM_DISPLAY_NAME} isn't installed yet.\n\n\
                 Open **Settings → Assistant** to download the on-device model (~4.3 GB), then ask again."
            )
        } else {
            fallback.complete(&req.messages, max_tokens)?
        };
        for chunk in openai_compat::chunk_text(&content, 48) {
            on_chunk.lock()(&chunk);
        }
        self.health.lock().record(true);
        Ok(ChatCompletionResponse {
            content,
            backend: format!("local-fallback-{device}"),
        })
    }

    pub fn chat(&self, req: ChatCompletionRequest) -> Result<ChatCompletionResponse> {
        tauri::async_runtime::block_on(self.chat_async(req))
    }

    /// Synchronous completion for tool planning (no streaming).
    pub fn complete_sync(&self, messages: &[ChatMessage], max_tokens: u32) -> Result<String> {
        if self.local_llm.is_installed() && self.local_llm.is_server_installed() {
            match tauri::async_runtime::block_on(self.local_llm.chat(messages, max_tokens)) {
                Ok(content) if !content.trim().is_empty() => return Ok(content),
                Ok(_) => {}
                Err(e) => tracing::warn!(error = %e, "sync LLM complete failed"),
            }
        }
        self.fallback.complete(messages, max_tokens)
    }
}

/// Deterministic portable embeddings / chat used as secondary fallback.
#[derive(Clone)]
pub struct PortableFallbackRuntime;

impl PortableFallbackRuntime {
    pub fn new() -> Self {
        Self
    }

    pub fn hash_embed(text: &str, dims: usize) -> Vec<f32> {
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
        Ok(texts
            .iter()
            .map(|t| Self::hash_embed(t, EMBED_DIMS))
            .collect())
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
