use crate::ai::{AiRuntimeStatus, ChatCompletionRequest, ChatCompletionResponse};
use crate::ai::openai_compat::PingResult;
use crate::commands::CmdResult;
use crate::AppState;
use serde::Serialize;
use tauri::State;

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SemanticHit {
    pub id: String,
    pub code: String,
    pub title: String,
    pub description: String,
    pub score: f32,
}

fn cosine(a: &[f32], b: &[f32]) -> f32 {
    let n = a.len().min(b.len());
    if n == 0 {
        return 0.0;
    }
    let mut dot = 0.0f32;
    let mut na = 0.0f32;
    let mut nb = 0.0f32;
    for i in 0..n {
        dot += a[i] * b[i];
        na += a[i] * a[i];
        nb += b[i] * b[i];
    }
    if na == 0.0 || nb == 0.0 {
        return 0.0;
    }
    dot / (na.sqrt() * nb.sqrt())
}

#[tauri::command]
pub fn ai_runtime_status(state: State<'_, AppState>) -> AiRuntimeStatus {
    state.ai.status()
}

#[tauri::command]
pub async fn ai_ping(state: State<'_, AppState>) -> CmdResult<PingResult> {
    state.ai.ping().await.map_err(Into::into)
}

#[tauri::command]
pub fn ai_embed_texts(state: State<'_, AppState>, texts: Vec<String>) -> CmdResult<Vec<Vec<f32>>> {
    state.ai.embed(&texts).map_err(Into::into)
}

#[tauri::command]
pub fn ai_chat_completion(
    state: State<'_, AppState>,
    request: ChatCompletionRequest,
) -> CmdResult<ChatCompletionResponse> {
    state.ai.chat(request).map_err(Into::into)
}

/// Rank catalog courses by embedding similarity to the query (hash/ONNX/MLX backend).
#[tauri::command]
pub fn ai_semantic_search_catalog(
    state: State<'_, AppState>,
    query: String,
    limit: Option<i64>,
) -> CmdResult<Vec<SemanticHit>> {
    let q = query.trim().to_string();
    if q.is_empty() {
        return Ok(vec![]);
    }
    let limit = limit.unwrap_or(12).clamp(1, 50) as usize;
    let courses: Vec<(String, String, String, String)> = state.db.with_conn(|conn| {
        let mut stmt = conn.prepare(
            "SELECT id, code, title, description FROM course_catalog
             ORDER BY code ASC LIMIT 400",
        )?;
        let rows = stmt
            .query_map([], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?)))?
            .collect::<Result<Vec<_>, _>>()?;
        Ok(rows)
    })?;
    if courses.is_empty() {
        return Ok(vec![]);
    }

    let mut texts = vec![q.clone()];
    for (_, code, title, description) in &courses {
        texts.push(format!("{code} {title} {description}"));
    }
    let embeds = state.ai.embed(&texts)?;
    let query_vec = embeds.first().cloned().unwrap_or_default();
    let mut scored: Vec<SemanticHit> = courses
        .into_iter()
        .enumerate()
        .filter_map(|(i, (id, code, title, description))| {
            let vec = embeds.get(i + 1)?;
            Some(SemanticHit {
                id,
                code,
                title,
                description,
                score: cosine(&query_vec, vec),
            })
        })
        .collect();
    scored.sort_by(|a, b| b.score.total_cmp(&a.score));
    scored.truncate(limit);
    Ok(scored)
}

/// Rank vault documents by embedding similarity to the query.
#[tauri::command]
pub fn ai_semantic_search_vault(
    state: State<'_, AppState>,
    query: String,
    limit: Option<i64>,
) -> CmdResult<Vec<SemanticHit>> {
    let q = query.trim().to_string();
    if q.is_empty() {
        return Ok(vec![]);
    }
    let limit = limit.unwrap_or(12).clamp(1, 50) as usize;
    let docs: Vec<(String, String, String, String)> = state.db.with_conn(|conn| {
        let mut stmt = conn.prepare(
            "SELECT id, category, title, mime_type FROM vault_document
             ORDER BY updated_at DESC LIMIT 400",
        )?;
        let rows = stmt
            .query_map([], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?)))?
            .collect::<Result<Vec<_>, _>>()?;
        Ok(rows)
    })?;
    if docs.is_empty() {
        return Ok(vec![]);
    }

    let mut texts = vec![q.clone()];
    for (_, category, title, mime) in &docs {
        texts.push(format!("{category} {title} {mime}"));
    }
    let embeds = state.ai.embed(&texts)?;
    let query_vec = embeds.first().cloned().unwrap_or_default();
    let mut scored: Vec<SemanticHit> = docs
        .into_iter()
        .enumerate()
        .filter_map(|(i, (id, code, title, description))| {
            let vec = embeds.get(i + 1)?;
            Some(SemanticHit {
                id,
                code,
                title,
                description,
                score: cosine(&query_vec, vec),
            })
        })
        .collect();
    scored.sort_by(|a, b| b.score.total_cmp(&a.score));
    scored.truncate(limit);
    Ok(scored)
}
