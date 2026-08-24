use crate::commands::CmdResult;
use crate::db::DbChangeEvent;
use crate::scrapers::{fetch_html, CourseLeafCourse, CourseLeafScraper};
use crate::AppState;
use chrono::Utc;
use rusqlite::OptionalExtension;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::sync::Arc;
use tauri::{AppHandle, Emitter, State};
use uuid::Uuid;

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct UniversityDto {
    pub id: String,
    pub name: String,
    pub short_name: String,
    pub domain: String,
    pub is_active: bool,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DepartmentDto {
    pub id: String,
    pub university_id: String,
    pub name: String,
    pub code: String,
    pub course_count: i64,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CourseDto {
    pub id: String,
    pub code: String,
    pub title: String,
    pub credits: Option<f64>,
    pub description: String,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CatalogIngestInput {
    pub url: String,
    pub university_id: Option<String>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CatalogIngestResult {
    pub imported: i64,
    pub skipped: i64,
    pub university_id: String,
    pub source_title: String,
}

fn emit_catalog(app: &AppHandle, revision: i64) {
    let _ = app.emit(
        "db:change",
        DbChangeEvent {
            domain: "catalog".into(),
            revision,
        },
    );
}

#[tauri::command]
pub fn catalog_list_universities(state: State<'_, AppState>) -> CmdResult<Vec<UniversityDto>> {
    state
        .db
        .with_conn(|conn| {
            let mut stmt = conn.prepare(
                "SELECT id, name, short_name, domain, is_active FROM university
                 ORDER BY name ASC LIMIT 200",
            )?;
            let rows = stmt
                .query_map([], |r| {
                    Ok(UniversityDto {
                        id: r.get(0)?,
                        name: r.get(1)?,
                        short_name: r.get(2)?,
                        domain: r.get(3)?,
                        is_active: r.get::<_, i64>(4)? != 0,
                    })
                })?
                .collect::<Result<Vec<_>, _>>()?;
            Ok(rows)
        })
        .map_err(Into::into)
}

#[tauri::command]
pub fn catalog_list_departments(
    state: State<'_, AppState>,
    university_id: String,
) -> CmdResult<Vec<DepartmentDto>> {
    state
        .db
        .with_conn(|conn| {
            let mut stmt = conn.prepare(
                "SELECT d.id, d.university_id, d.name, d.code,
                        (SELECT COUNT(1) FROM course_catalog c WHERE c.department_id = d.id) AS course_count
                 FROM department d
                 WHERE d.university_id = ?1
                 ORDER BY d.code ASC, d.name ASC
                 LIMIT 300",
            )?;
            let rows = stmt
                .query_map([&university_id], |r| {
                    Ok(DepartmentDto {
                        id: r.get(0)?,
                        university_id: r.get(1)?,
                        name: r.get(2)?,
                        code: r.get(3)?,
                        course_count: r.get(4)?,
                    })
                })?
                .collect::<Result<Vec<_>, _>>()?;
            Ok(rows)
        })
        .map_err(Into::into)
}

#[tauri::command]
pub fn catalog_list_department_courses(
    state: State<'_, AppState>,
    department_id: String,
) -> CmdResult<Vec<CourseDto>> {
    state
        .db
        .with_conn(|conn| {
            let mut stmt = conn.prepare(
                "SELECT id, code, title, credits, description FROM course_catalog
                 WHERE department_id = ?1
                 ORDER BY code ASC LIMIT 200",
            )?;
            let rows = stmt
                .query_map([&department_id], |r| {
                    Ok(CourseDto {
                        id: r.get(0)?,
                        code: r.get(1)?,
                        title: r.get(2)?,
                        credits: r.get(3)?,
                        description: r.get(4)?,
                    })
                })?
                .collect::<Result<Vec<_>, _>>()?;
            Ok(rows)
        })
        .map_err(Into::into)
}

#[tauri::command]
pub fn catalog_search_courses(
    state: State<'_, AppState>,
    query: String,
) -> CmdResult<Vec<CourseDto>> {
    let trimmed = query.trim().to_string();
    state
        .db
        .with_conn(|conn| {
            if trimmed.is_empty() {
                let mut stmt = conn.prepare(
                    "SELECT id, code, title, credits, description FROM course_catalog
                     ORDER BY code ASC LIMIT 100",
                )?;
                let rows = stmt
                    .query_map([], |r| {
                        Ok(CourseDto {
                            id: r.get(0)?,
                            code: r.get(1)?,
                            title: r.get(2)?,
                            credits: r.get(3)?,
                            description: r.get(4)?,
                        })
                    })?
                    .collect::<Result<Vec<_>, _>>()?;
                return Ok(rows);
            }
            let q = format!("%{trimmed}%");
            let mut stmt = conn.prepare(
                "SELECT id, code, title, credits, description FROM course_catalog
                 WHERE code LIKE ?1 OR title LIKE ?1 OR description LIKE ?1
                 ORDER BY code ASC LIMIT 100",
            )?;
            let rows = stmt
                .query_map([&q], |r| {
                    Ok(CourseDto {
                        id: r.get(0)?,
                        code: r.get(1)?,
                        title: r.get(2)?,
                        credits: r.get(3)?,
                        description: r.get(4)?,
                    })
                })?
                .collect::<Result<Vec<_>, _>>()?;
            Ok(rows)
        })
        .map_err(Into::into)
}

fn ingest_signature(body: &str) -> String {
    let mut hasher = Sha256::new();
    hasher.update(body.as_bytes());
    format!("{:x}", hasher.finalize())
}

fn parse_courses_from_body(body: &str) -> Vec<CourseLeafCourse> {
    let mut parsed: Vec<CourseLeafCourse> = CourseLeafScraper::parse_courses(body);
    if parsed.is_empty() {
        if let Ok(re) =
            regex::Regex::new(r"(?m)\b([A-Z]{2,4})\s*[- ]?\s*(\d{3}[A-Z]?)\b[^\n]{0,80}")
        {
            for cap in re.captures_iter(body) {
                let code = format!("{} {}", &cap[1], &cap[2]);
                let line = cap.get(0).map(|m| m.as_str()).unwrap_or("").trim();
                parsed.push(CourseLeafCourse {
                    code,
                    title: line.chars().take(120).collect(),
                    credits: None,
                    description: line.chars().take(400).collect(),
                });
            }
        }
    }
    parsed
}

fn persist_catalog_courses(
    state: &AppState,
    input: &CatalogIngestInput,
    parsed: &[CourseLeafCourse],
) -> CmdResult<(i64, i64, String)> {
    let mut imported = 0i64;
    let mut skipped = 0i64;
    let university_id = state.db.with_conn(|conn| {
        let uni_id = if let Some(id) = input.university_id.clone().filter(|s| !s.is_empty()) {
            id
        } else {
            match conn.query_row(
                "SELECT id FROM university ORDER BY name ASC LIMIT 1",
                [],
                |r| r.get::<_, String>(0),
            ) {
                Ok(id) => id,
                Err(_) => {
                    let id = Uuid::new_v4().to_string();
                    conn.execute(
                        "INSERT INTO university (id, name, short_name, domain, catalog_base_url, is_active)
                         VALUES (?1, 'Imported Catalog', 'Import', '', ?2, 1)",
                        rusqlite::params![id, input.url],
                    )?;
                    id
                }
            }
        };

        for course in parsed {
            let exists: i64 = conn.query_row(
                "SELECT COUNT(1) FROM course_catalog WHERE university_id = ?1 AND code = ?2",
                rusqlite::params![uni_id, course.code],
                |r| r.get(0),
            )?;
            if exists > 0 {
                skipped += 1;
                continue;
            }
            let id = Uuid::new_v4().to_string();
            conn.execute(
                "INSERT INTO course_catalog
                 (id, university_id, department_id, code, title, credits, description, prerequisites, is_archived, stable_id)
                 VALUES (?1, ?2, NULL, ?3, ?4, ?5, ?6, '', 0, NULL)",
                rusqlite::params![
                    id,
                    uni_id,
                    course.code,
                    course.title,
                    course.credits,
                    course.description
                ],
            )?;
            imported += 1;
        }
        Ok::<_, anyhow::Error>(uni_id)
    })?;
    Ok((imported, skipped, university_id))
}

/// Fetch a catalog URL, parse CourseLeaf heuristics + code regex, persist new courses.
#[tauri::command]
pub async fn catalog_ingest_url(
    app: AppHandle,
    state: State<'_, AppState>,
    input: CatalogIngestInput,
) -> CmdResult<CatalogIngestResult> {
    let (preview, body) = fetch_html(&input.url).await?;
    let parsed = parse_courses_from_body(&body);
    let (imported, skipped, university_id) = persist_catalog_courses(&state, &input, &parsed)?;

    let rev = state.db.bump_revision("catalog")?;
    emit_catalog(&app, rev);
    if imported > 0 {
        spawn_catalog_reindex(app.clone(), Arc::new(state.inner().clone()), imported);
    }
    Ok(CatalogIngestResult {
        imported,
        skipped,
        university_id,
        source_title: preview.title,
    })
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CatalogUniversitySyncRow {
    pub id: String,
    pub name: String,
    pub catalog_base_url: String,
    pub course_count: i64,
    pub last_synced_at: Option<String>,
    pub last_imported: i64,
    pub last_skipped: i64,
    pub last_signature: Option<String>,
    pub last_error: Option<String>,
    pub unchanged: bool,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CatalogSyncDiagnostics {
    pub universities: Vec<CatalogUniversitySyncRow>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CatalogSyncUniversityInput {
    pub university_id: String,
    pub force: Option<bool>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CatalogSyncUniversityResult {
    pub university_id: String,
    pub imported: i64,
    pub skipped: i64,
    pub unchanged: bool,
    pub source_title: String,
    pub synced_at: String,
}

fn sync_settings_key(university_id: &str) -> String {
    format!("catalog.sync.{university_id}")
}

fn read_sync_meta(state: &AppState, university_id: &str) -> Option<serde_json::Value> {
    state
        .db
        .with_conn(|conn| {
            let raw: Option<String> = conn
                .query_row(
                    "SELECT value FROM app_settings WHERE key = ?1",
                    rusqlite::params![sync_settings_key(university_id)],
                    |r| r.get(0),
                )
                .optional()?;
            Ok(raw)
        })
        .ok()
        .flatten()
        .and_then(|s| serde_json::from_str(&s).ok())
}

fn write_sync_meta(
    state: &AppState,
    university_id: &str,
    meta: &serde_json::Value,
) -> CmdResult<()> {
    let now = Utc::now().to_rfc3339();
    let key = sync_settings_key(university_id);
    let value = meta.to_string();
    state.db.with_conn(|conn| {
        conn.execute(
            "INSERT INTO app_settings (key, value, updated_at) VALUES (?1, ?2, ?3)
             ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at",
            rusqlite::params![key, value, now],
        )?;
        Ok(())
    })?;
    Ok(())
}

#[tauri::command]
pub fn catalog_get_sync_diagnostics(state: State<'_, AppState>) -> CmdResult<CatalogSyncDiagnostics> {
    let universities: Vec<(String, String, String, i64)> = state
        .db
        .with_conn(|conn| {
            let mut stmt = conn.prepare(
                "SELECT u.id, u.name, u.catalog_base_url,
                        (SELECT COUNT(*) FROM course_catalog c WHERE c.university_id = u.id)
                 FROM university u
                 ORDER BY u.name ASC
                 LIMIT 200",
            )?;
            let rows = stmt
                .query_map([], |r| {
                    Ok((
                        r.get::<_, String>(0)?,
                        r.get::<_, String>(1)?,
                        r.get::<_, String>(2)?,
                        r.get::<_, i64>(3)?,
                    ))
                })?
                .collect::<Result<Vec<_>, _>>()?;
            Ok(rows)
        })
        .map_err(|e| anyhow::anyhow!(e))?;

    let rows = universities
        .into_iter()
        .map(|(id, name, catalog_base_url, course_count)| {
            let meta = read_sync_meta(&state, &id);
            CatalogUniversitySyncRow {
                id,
                name,
                catalog_base_url,
                course_count,
                last_synced_at: meta
                    .as_ref()
                    .and_then(|m| m.get("syncedAt"))
                    .and_then(|v| v.as_str())
                    .map(String::from),
                last_imported: meta
                    .as_ref()
                    .and_then(|m| m.get("imported"))
                    .and_then(|v| v.as_i64())
                    .unwrap_or(0),
                last_skipped: meta
                    .as_ref()
                    .and_then(|m| m.get("skipped"))
                    .and_then(|v| v.as_i64())
                    .unwrap_or(0),
                last_signature: meta
                    .as_ref()
                    .and_then(|m| m.get("signature"))
                    .and_then(|v| v.as_str())
                    .map(String::from),
                last_error: meta
                    .as_ref()
                    .and_then(|m| m.get("error"))
                    .and_then(|v| v.as_str())
                    .map(String::from),
                unchanged: meta
                    .as_ref()
                    .and_then(|m| m.get("unchanged"))
                    .and_then(|v| v.as_bool())
                    .unwrap_or(false),
            }
        })
        .collect();

    Ok(CatalogSyncDiagnostics { universities: rows })
}

/// Background-style catalog sync for a university using its catalog_base_url.
#[tauri::command]
pub async fn catalog_sync_university(
    app: AppHandle,
    state: State<'_, AppState>,
    input: CatalogSyncUniversityInput,
) -> CmdResult<CatalogSyncUniversityResult> {
    let force = input.force.unwrap_or(false);
    let (name, catalog_url): (String, String) = state.db.with_conn(|conn| {
        conn.query_row(
            "SELECT name, catalog_base_url FROM university WHERE id = ?1",
            rusqlite::params![input.university_id],
            |r| Ok((r.get(0)?, r.get(1)?)),
        )
        .map_err(Into::into)
    })?;

    let url = catalog_url.trim();
    if url.is_empty() {
        return Err(anyhow::anyhow!("{name} has no catalog_base_url configured").into());
    }

    let (preview, body) = fetch_html(url).await?;
    let signature = ingest_signature(&body);
    if !force {
        if let Some(meta) = read_sync_meta(&state, &input.university_id) {
            if meta.get("signature").and_then(|v| v.as_str()) == Some(signature.as_str()) {
                let now = Utc::now().to_rfc3339();
                write_sync_meta(
                    &state,
                    &input.university_id,
                    &serde_json::json!({
                        "syncedAt": now,
                        "imported": 0,
                        "skipped": 0,
                        "signature": signature,
                        "unchanged": true,
                        "sourceTitle": preview.title,
                    }),
                )?;
                return Ok(CatalogSyncUniversityResult {
                    university_id: input.university_id,
                    imported: 0,
                    skipped: 0,
                    unchanged: true,
                    source_title: preview.title,
                    synced_at: now,
                });
            }
        }
    }

    let parsed = parse_courses_from_body(&body);
    let ingest_input = CatalogIngestInput {
        url: url.to_string(),
        university_id: Some(input.university_id.clone()),
    };
    let (imported, skipped, _) = persist_catalog_courses(&state, &ingest_input, &parsed)?;
    let rev = state.db.bump_revision("catalog")?;
    emit_catalog(&app, rev);

    if imported > 0 {
        spawn_catalog_reindex(app.clone(), Arc::new(state.inner().clone()), imported);
    }

    let now = Utc::now().to_rfc3339();
    write_sync_meta(
        &state,
        &input.university_id,
        &serde_json::json!({
            "syncedAt": now,
            "imported": imported,
            "skipped": skipped,
            "signature": signature,
            "unchanged": imported == 0,
            "sourceTitle": preview.title,
        }),
    )?;

    Ok(CatalogSyncUniversityResult {
        university_id: input.university_id,
        imported,
        skipped,
        unchanged: imported == 0,
        source_title: preview.title,
        synced_at: now,
    })
}

fn cosine_similarity(a: &[f32], b: &[f32]) -> f32 {
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

fn embedding_model_tag(state: &AppState) -> String {
    state.ai.status().embeddings_backend
}

fn course_embed_text(code: &str, title: &str, description: &str) -> String {
    format!("{code} {title} {description}")
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CatalogEmbeddingStats {
    pub indexed_count: i64,
    pub course_count: i64,
    pub model_tag: String,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CatalogReindexResult {
    pub indexed: i64,
    pub skipped: i64,
    pub model_tag: String,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CatalogSemanticHit {
    pub id: String,
    pub code: String,
    pub title: String,
    pub description: String,
    pub score: f32,
}

pub(crate) fn reindex_catalog_embeddings(state: &AppState, limit: i64) -> CmdResult<CatalogReindexResult> {
    let model_tag = embedding_model_tag(state);
    let limit = limit.clamp(1, 500);

    let courses: Vec<(String, String, String, String)> = state.db.with_conn(|conn| {
        let mut stmt = conn.prepare(
            "SELECT c.id, c.code, c.title, c.description
             FROM course_catalog c
             LEFT JOIN catalog_course_embedding e ON e.course_id = c.id AND e.model_tag = ?1
             WHERE e.course_id IS NULL
             ORDER BY c.code ASC
             LIMIT ?2",
        )?;
        let rows = stmt
            .query_map(rusqlite::params![model_tag, limit], |r| {
                Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?))
            })?
            .collect::<Result<Vec<_>, _>>()?;
        Ok(rows)
    })?;

    if courses.is_empty() {
        return Ok(CatalogReindexResult {
            indexed: 0,
            skipped: 0,
            model_tag,
        });
    }

    let texts: Vec<String> = courses
        .iter()
        .map(|(_, code, title, description)| course_embed_text(code, title, description))
        .collect();
    let vectors = state.ai.embed(&texts)?;
    let now = Utc::now().to_rfc3339();
    let mut indexed = 0i64;

    state.db.with_conn(|conn| {
        for ((course_id, _, _, _), vec) in courses.iter().zip(vectors.iter()) {
            let vector_json = serde_json::to_string(vec)?;
            conn.execute(
                "INSERT INTO catalog_course_embedding (course_id, model_tag, vector_json, updated_at)
                 VALUES (?1, ?2, ?3, ?4)
                 ON CONFLICT(course_id) DO UPDATE SET
                   model_tag = excluded.model_tag,
                   vector_json = excluded.vector_json,
                   updated_at = excluded.updated_at",
                rusqlite::params![course_id, model_tag, vector_json, now],
            )?;
            indexed += 1;
        }
        Ok(())
    })?;

    Ok(CatalogReindexResult {
        indexed,
        skipped: 0,
        model_tag,
    })
}

fn spawn_catalog_reindex(app: AppHandle, state: Arc<AppState>, limit: i64) {
    tauri::async_runtime::spawn(async move {
        match reindex_catalog_embeddings(state.as_ref(), limit) {
            Ok(res) => {
                tracing::info!(
                    indexed = res.indexed,
                    model = %res.model_tag,
                    "catalog embedding reindex finished"
                );
                if res.indexed > 0 {
                    if let Ok(rev) = state.db.bump_revision("catalog") {
                        let _ = app.emit(
                            "db:change",
                            DbChangeEvent {
                                domain: "catalog".into(),
                                revision: rev,
                            },
                        );
                    }
                }
            }
            Err(e) => tracing::warn!(error = %e.message, "catalog embedding reindex failed"),
        }
    });
}

#[tauri::command]
pub fn catalog_embedding_stats(state: State<'_, AppState>) -> CmdResult<CatalogEmbeddingStats> {
    let model_tag = embedding_model_tag(state.inner());
    state
        .db
        .with_conn(|conn| {
            let course_count: i64 =
                conn.query_row("SELECT COUNT(*) FROM course_catalog", [], |r| r.get(0))?;
            let indexed_count: i64 = conn.query_row(
                "SELECT COUNT(*) FROM catalog_course_embedding WHERE model_tag = ?1",
                rusqlite::params![model_tag],
                |r| r.get(0),
            )?;
            Ok(CatalogEmbeddingStats {
                indexed_count,
                course_count,
                model_tag,
            })
        })
        .map_err(Into::into)
}

#[tauri::command]
pub fn catalog_reindex_embeddings(
    app: AppHandle,
    state: State<'_, AppState>,
    limit: Option<i64>,
) -> CmdResult<CatalogReindexResult> {
    let result = reindex_catalog_embeddings(state.inner(), limit.unwrap_or(500))?;
    if result.indexed > 0 {
        let rev = state.db.bump_revision("catalog")?;
        emit_catalog(&app, rev);
    }
    Ok(result)
}

#[tauri::command]
pub fn catalog_semantic_search(
    state: State<'_, AppState>,
    query: String,
    limit: Option<i64>,
) -> CmdResult<Vec<CatalogSemanticHit>> {
    let q = query.trim().to_string();
    if q.is_empty() {
        return Ok(vec![]);
    }
    let limit = limit.unwrap_or(12).clamp(1, 50) as usize;
    let model_tag = embedding_model_tag(state.inner());

    let indexed_count: i64 = state.db.with_conn(|conn| {
        conn.query_row(
            "SELECT COUNT(*) FROM catalog_course_embedding WHERE model_tag = ?1",
            rusqlite::params![model_tag],
            |r| r.get(0),
        )
        .map_err(Into::into)
    })?;

    if indexed_count == 0 {
        let like = format!("%{q}%");
        let fallback: Vec<CatalogSemanticHit> = state.db.with_conn(|conn| {
            let mut stmt = conn.prepare(
                "SELECT id, code, title, description FROM course_catalog
                 WHERE code LIKE ?1 OR title LIKE ?1 OR description LIKE ?1
                 ORDER BY code ASC LIMIT ?2",
            )?;
            let rows = stmt
                .query_map(rusqlite::params![like, limit as i64], |r| {
                    Ok(CatalogSemanticHit {
                        id: r.get(0)?,
                        code: r.get(1)?,
                        title: r.get(2)?,
                        description: r.get(3)?,
                        score: 0.5,
                    })
                })?
                .collect::<Result<Vec<_>, _>>()?;
            Ok(rows)
        })?;
        return Ok(fallback);
    }

    let query_vec = state.ai.embed(&[q.clone()])?.into_iter().next().unwrap_or_default();

    let rows: Vec<(String, String, String, String, String)> = state.db.with_conn(|conn| {
        let mut stmt = conn.prepare(
            "SELECT c.id, c.code, c.title, c.description, e.vector_json
             FROM catalog_course_embedding e
             JOIN course_catalog c ON c.id = e.course_id
             WHERE e.model_tag = ?1",
        )?;
        let mapped = stmt.query_map(rusqlite::params![model_tag], |r| {
            Ok((
                r.get(0)?,
                r.get(1)?,
                r.get(2)?,
                r.get(3)?,
                r.get(4)?,
            ))
        })?;
        mapped.collect::<Result<Vec<_>, _>>().map_err(Into::into)
    })?;

    let mut scored: Vec<CatalogSemanticHit> = rows
        .into_iter()
        .filter_map(|(id, code, title, description, vector_json)| {
            let vec: Vec<f32> = serde_json::from_str(&vector_json).ok()?;
            Some(CatalogSemanticHit {
                id,
                code,
                title,
                description,
                score: cosine_similarity(&query_vec, &vec),
            })
        })
        .collect();
    scored.sort_by(|a, b| b.score.total_cmp(&a.score));
    scored.truncate(limit);
    Ok(scored)
}
