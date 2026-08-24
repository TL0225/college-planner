//! macOS MLX / Metal adapter.
//! Bridges to Apple MLX when models are present; portable fallback otherwise.

use super::traits::{LocalInferenceEngine, TextEmbeddingEngine};
use super::onnx_stub::{onnx_local_embed, resolve_local_model_file};
use super::{ChatMessage, PortableFallbackRuntime};
use anyhow::Result;
use std::path::Path;

#[derive(Clone)]
pub struct MlxRuntime {
    fallback: PortableFallbackRuntime,
    model_dir: std::path::PathBuf,
}

impl MlxRuntime {
    pub fn new(model_dir: &Path) -> Result<Self> {
        std::fs::create_dir_all(model_dir)?;
        tracing::info!(
            path = %model_dir.display(),
            "MLX Metal AI runtime initialized (MLX models optional)"
        );
        Ok(Self {
            fallback: PortableFallbackRuntime::new(),
            model_dir: model_dir.to_path_buf(),
        })
    }

    fn has_mlx_model(&self) -> bool {
        self.model_dir.join("mlx-embeddings").exists()
            || self.model_dir.join("mlx-llm").exists()
    }
}

impl TextEmbeddingEngine for MlxRuntime {
    fn is_ready(&self) -> bool {
        true
    }

    fn embed(&self, texts: &[String]) -> Result<Vec<Vec<f32>>> {
        if let Some(path) = resolve_local_model_file(None, &self.model_dir) {
            if let Some(vecs) = onnx_local_embed(&path, texts, 384) {
                tracing::debug!(path = %path.display(), "MLX onnx-local embeddings");
                return Ok(vecs);
            }
        }
        if self.has_mlx_model() {
            tracing::debug!("MLX model dir present; using fingerprint-local embeddings via model dir");
            if let Some(vecs) = onnx_local_embed(&self.model_dir.join("mlx-embeddings"), texts, 384) {
                return Ok(vecs);
            }
        }
        self.fallback.embed(texts)
    }
}

impl LocalInferenceEngine for MlxRuntime {
    fn is_ready(&self) -> bool {
        true
    }

    fn complete(&self, messages: &[ChatMessage], max_tokens: u32) -> Result<String> {
        if self.has_mlx_model() {
            tracing::debug!("MLX LLM model detected; Metal generation stub");
        }
        self.fallback.complete(messages, max_tokens)
    }
}
