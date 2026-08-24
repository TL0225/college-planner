//! Windows DirectML / ONNX Runtime adapter.
//! Uses portable deterministic embeddings until ONNX models are present.

use super::traits::{LocalInferenceEngine, TextEmbeddingEngine};
use super::onnx_stub::{onnx_local_embed, resolve_local_model_file};
use super::{ChatMessage, PortableFallbackRuntime};
use anyhow::Result;
use std::path::Path;

#[derive(Clone)]
pub struct DirectMlRuntime {
    fallback: PortableFallbackRuntime,
    model_dir: std::path::PathBuf,
}

impl DirectMlRuntime {
    pub fn new(model_dir: &Path) -> Result<Self> {
        std::fs::create_dir_all(model_dir)?;
        tracing::info!(
            path = %model_dir.display(),
            "DirectML AI runtime initialized (ONNX models optional)"
        );
        Ok(Self {
            fallback: PortableFallbackRuntime::new(),
            model_dir: model_dir.to_path_buf(),
        })
    }

    fn has_onnx_model(&self) -> bool {
        self.model_dir.join("embeddings.onnx").exists()
            || self.model_dir.join("llm.onnx").exists()
    }
}

impl TextEmbeddingEngine for DirectMlRuntime {
    fn is_ready(&self) -> bool {
        true
    }

    fn embed(&self, texts: &[String]) -> Result<Vec<Vec<f32>>> {
        if let Some(path) = resolve_local_model_file(None, &self.model_dir) {
            if let Some(vecs) = onnx_local_embed(&path, texts, 384) {
                tracing::debug!(path = %path.display(), "DirectML onnx-local embeddings");
                return Ok(vecs);
            }
        }
        self.fallback.embed(texts)
    }
}

impl LocalInferenceEngine for DirectMlRuntime {
    fn is_ready(&self) -> bool {
        true
    }

    fn complete(&self, messages: &[ChatMessage], max_tokens: u32) -> Result<String> {
        if self.has_onnx_model() {
            tracing::debug!("ONNX LLM model detected; DirectML generation stub");
        }
        self.fallback.complete(messages, max_tokens)
    }
}
