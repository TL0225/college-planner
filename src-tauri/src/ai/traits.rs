use anyhow::Result;
use super::{ChatMessage};

pub trait TextEmbeddingEngine: Send + Sync {
    fn is_ready(&self) -> bool;
    fn embed(&self, texts: &[String]) -> Result<Vec<Vec<f32>>>;
}

pub trait LocalInferenceEngine: Send + Sync {
    fn is_ready(&self) -> bool;
    fn complete(&self, messages: &[ChatMessage], max_tokens: u32) -> Result<String>;
}
