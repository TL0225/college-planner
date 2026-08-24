use crate::commands::CmdResult;
use crate::db::DbChangeEvent;
use crate::AppState;
use serde::{Deserialize, Serialize};
use tauri::{AppHandle, Emitter, State};
use uuid::Uuid;

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct TransferEquivalencyDto {
    pub id: String,
    pub source_school: String,
    pub source_code: String,
    pub target_code: String,
    pub credits: Option<f64>,
    pub notes: String,
    pub proof_document_id: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UpsertTransferInput {
    pub source_school: String,
    pub source_code: String,
    pub target_code: String,
    pub credits: Option<f64>,
    pub notes: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ImportTransferRow {
    pub source_school: String,
    pub source_code: String,
    pub target_code: String,
    pub credits: Option<f64>,
    pub notes: Option<String>,
}

fn upsert_equivalency_row(
    conn: &rusqlite::Connection,
    input: &UpsertTransferInput,
) -> rusqlite::Result<String> {
    let id = Uuid::new_v4().to_string();
    let dedupe = format!(
        "{}|{}|{}",
        input.source_school.trim().to_ascii_lowercase(),
        input.source_code.trim().to_ascii_uppercase(),
        input.target_code.trim().to_ascii_uppercase()
    );
    conn.execute(
        "INSERT INTO transfer_equivalency
         (id, source_school, source_code, target_code, credits, notes, dedupe_key, proof_document_id)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, NULL)
         ON CONFLICT(dedupe_key) DO UPDATE SET
           credits = excluded.credits,
           notes = excluded.notes",
        rusqlite::params![
            id,
            input.source_school.trim(),
            input.source_code.trim(),
            input.target_code.trim(),
            input.credits,
            input.notes.as_deref().unwrap_or(""),
            dedupe
        ],
    )?;
    conn.query_row(
        "SELECT id FROM transfer_equivalency WHERE dedupe_key = ?1",
        rusqlite::params![dedupe],
        |r| r.get(0),
    )
}

fn bump_transfer(app: &AppHandle, state: &AppState) -> CmdResult<()> {
    let rev = state.db.bump_revision("transfer")?;
    let _ = app.emit(
        "db:change",
        DbChangeEvent {
            domain: "transfer".to_string(),
            revision: rev,
        },
    );
    Ok(())
}

#[tauri::command]
pub fn transfer_list_equivalencies(
    state: State<'_, AppState>,
) -> CmdResult<Vec<TransferEquivalencyDto>> {
    state
        .db
        .with_conn(|conn| {
            let mut stmt = conn.prepare(
                "SELECT id, source_school, source_code, target_code, credits, notes, proof_document_id
                 FROM transfer_equivalency
                 ORDER BY source_school ASC, source_code ASC
                 LIMIT 400",
            )?;
            let rows = stmt
                .query_map([], |r| {
                    Ok(TransferEquivalencyDto {
                        id: r.get(0)?,
                        source_school: r.get(1)?,
                        source_code: r.get(2)?,
                        target_code: r.get(3)?,
                        credits: r.get(4)?,
                        notes: r.get(5)?,
                        proof_document_id: r.get(6)?,
                    })
                })?
                .collect::<Result<Vec<_>, _>>()?;
            Ok(rows)
        })
        .map_err(Into::into)
}

#[tauri::command]
pub fn transfer_upsert_equivalency(
    app: AppHandle,
    state: State<'_, AppState>,
    input: UpsertTransferInput,
) -> CmdResult<String> {
    let resolved = state
        .db
        .with_conn(|conn| Ok(upsert_equivalency_row(conn, &input)?))?;
    bump_transfer(&app, &state)?;
    Ok(resolved)
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ImportTransferResult {
    pub imported: i64,
    pub skipped: i64,
}

#[tauri::command]
pub fn transfer_import_equivalencies(
    app: AppHandle,
    state: State<'_, AppState>,
    rows: Vec<ImportTransferRow>,
) -> CmdResult<ImportTransferResult> {
    let result = state
        .db
        .with_conn(|conn| Ok(import_equivalency_rows(conn, &rows)?))?;
    bump_transfer(&app, &state)?;
    Ok(result)
}

fn import_equivalency_rows(
    conn: &rusqlite::Connection,
    rows: &[ImportTransferRow],
) -> rusqlite::Result<ImportTransferResult> {
    let mut imported = 0i64;
    let mut skipped = 0i64;
    for row in rows {
        let source_school = row.source_school.trim();
        let source_code = row.source_code.trim();
        let target_code = row.target_code.trim();
        if source_school.is_empty() || source_code.is_empty() || target_code.is_empty() {
            skipped += 1;
            continue;
        }
        let input = UpsertTransferInput {
            source_school: source_school.to_string(),
            source_code: source_code.to_string(),
            target_code: target_code.to_string(),
            credits: row.credits,
            notes: row.notes.clone(),
        };
        upsert_equivalency_row(conn, &input)?;
        imported += 1;
    }
    Ok(ImportTransferResult { imported, skipped })
}

#[tauri::command]
pub fn transfer_delete_equivalency(
    app: AppHandle,
    state: State<'_, AppState>,
    id: String,
) -> CmdResult<()> {
    state.db.with_conn(|conn| {
        conn.execute(
            "DELETE FROM transfer_equivalency WHERE id = ?1",
            rusqlite::params![id],
        )?;
        Ok(())
    })?;
    bump_transfer(&app, &state)?;
    Ok(())
}

#[tauri::command]
pub fn transfer_link_proof_document(
    app: AppHandle,
    state: State<'_, AppState>,
    equivalency_id: String,
    vault_document_id: Option<String>,
) -> CmdResult<()> {
    state.db.with_conn(|conn| {
        conn.execute(
            "UPDATE transfer_equivalency SET proof_document_id = ?1 WHERE id = ?2",
            rusqlite::params![vault_document_id, equivalency_id],
        )?;
        Ok(())
    })?;
    bump_transfer(&app, &state)?;
    Ok(())
}

#[derive(Debug, Deserialize)]
struct CommunityPayload {
    equivalencies: Option<Vec<ImportTransferRow>>,
}

#[derive(Debug, Deserialize)]
struct CommunityRowAlt {
    #[serde(rename = "sourceSchool")]
    source_school: Option<String>,
    #[serde(rename = "sourceSchoolID")]
    source_school_id: Option<String>,
    #[serde(rename = "sourceCode")]
    source_code: Option<String>,
    #[serde(rename = "sourceCourseCode")]
    source_course_code: Option<String>,
    #[serde(rename = "targetCode")]
    target_code: Option<String>,
    #[serde(rename = "targetCourseCode")]
    target_course_code: Option<String>,
    credits: Option<f64>,
    notes: Option<String>,
}

fn community_row_to_import(row: CommunityRowAlt) -> Option<ImportTransferRow> {
    let source_school = row
        .source_school
        .or(row.source_school_id)?
        .trim()
        .to_string();
    let source_code = row
        .source_code
        .or(row.source_course_code)?
        .trim()
        .to_string();
    let target_code = row
        .target_code
        .or(row.target_course_code)?
        .trim()
        .to_string();
    if source_school.is_empty() || source_code.is_empty() || target_code.is_empty() {
        return None;
    }
    Some(ImportTransferRow {
        source_school,
        source_code,
        target_code,
        credits: row.credits,
        notes: row.notes,
    })
}

#[tauri::command]
pub fn transfer_import_community_json(
    app: AppHandle,
    state: State<'_, AppState>,
    json_text: String,
) -> CmdResult<ImportTransferResult> {
    let trimmed = json_text.trim();
    if trimmed.is_empty() {
        return Err(crate::commands::CommandError {
            message: "Empty community JSON".into(),
        });
    }
    let rows: Vec<ImportTransferRow> = if let Ok(payload) = serde_json::from_str::<CommunityPayload>(trimmed) {
        payload.equivalencies.unwrap_or_default()
    } else if let Ok(list) = serde_json::from_str::<Vec<ImportTransferRow>>(trimmed) {
        list
    } else if let Ok(alt) = serde_json::from_str::<Vec<CommunityRowAlt>>(trimmed) {
        alt.into_iter().filter_map(community_row_to_import).collect()
    } else {
        return Err(crate::commands::CommandError {
            message: "Could not parse community JSON (expected array or {equivalencies:[]})".into(),
        });
    };
    let result = state
        .db
        .with_conn(|conn| Ok(import_equivalency_rows(conn, &rows)?))?;
    bump_transfer(&app, &state)?;
    Ok(result)
}

const ASSIST_SAMPLE_JSON: &str =
    include_str!("../../fixtures/assist_sample.json");

#[derive(Debug, Deserialize)]
struct AssistPayload {
    equivalencies: Option<Vec<AssistEquivalencyRow>>,
}

#[derive(Debug, Deserialize)]
struct AssistEquivalencyRow {
    #[serde(rename = "sourceSchoolName")]
    source_school_name: Option<String>,
    #[serde(rename = "source_school_name")]
    source_school_name_snake: Option<String>,
    #[serde(rename = "sourceCourseCode")]
    source_course_code: Option<String>,
    #[serde(rename = "source_course_code")]
    source_course_code_snake: Option<String>,
    #[serde(rename = "targetCourseCode")]
    target_course_code: Option<String>,
    #[serde(rename = "target_course_code")]
    target_course_code_snake: Option<String>,
    #[serde(rename = "sourceCredits")]
    source_credits: Option<f64>,
    #[serde(rename = "source_credits")]
    source_credits_snake: Option<f64>,
    #[serde(rename = "sourceCourseTitle")]
    source_course_title: Option<String>,
    #[serde(rename = "source_course_title")]
    source_course_title_snake: Option<String>,
}

fn assist_row_to_import(row: AssistEquivalencyRow) -> Option<ImportTransferRow> {
    let source_school = row
        .source_school_name
        .or(row.source_school_name_snake)?
        .trim()
        .to_string();
    let source_code = row
        .source_course_code
        .or(row.source_course_code_snake)?
        .trim()
        .to_string();
    let target_code = row
        .target_course_code
        .or(row.target_course_code_snake)?
        .trim()
        .to_string();
    if source_school.is_empty() || source_code.is_empty() || target_code.is_empty() {
        return None;
    }
    let title = row
        .source_course_title
        .or(row.source_course_title_snake)
        .unwrap_or_default();
    Some(ImportTransferRow {
        source_school,
        source_code,
        target_code,
        credits: row.source_credits.or(row.source_credits_snake),
        notes: if title.trim().is_empty() {
            Some("ASSIST import".into())
        } else {
            Some(format!("ASSIST: {title}"))
        },
    })
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TransferImportAssistInput {
    pub source_school_id: String,
    pub target_school_id: String,
    pub mode: Option<String>,
}

#[tauri::command]
pub async fn transfer_import_assist(
    app: AppHandle,
    state: State<'_, AppState>,
    input: TransferImportAssistInput,
) -> CmdResult<ImportTransferResult> {
    let source = input.source_school_id.trim().to_lowercase();
    let target = input.target_school_id.trim().to_lowercase();
    if source.is_empty() || target.is_empty() {
        return Err(crate::commands::CommandError {
            message: "Source and target school IDs required".into(),
        });
    }

    let json_text = if input.mode.as_deref() == Some("live") {
        let url = format!(
            "https://raw.githubusercontent.com/TL0225/college-planner-data/main/transfer/assist/{source}__{target}.json"
        );
        reqwest::get(&url)
            .await
            .map_err(|e| crate::commands::CommandError {
                message: format!("ASSIST fetch failed: {e}"),
            })?
            .text()
            .await
            .map_err(|e| crate::commands::CommandError {
                message: format!("ASSIST read failed: {e}"),
            })?
    } else {
        ASSIST_SAMPLE_JSON.to_string()
    };

    let payload: AssistPayload = serde_json::from_str(&json_text).map_err(|e| {
        crate::commands::CommandError {
            message: format!("ASSIST JSON parse failed: {e}"),
        }
    })?;
    let rows: Vec<ImportTransferRow> = payload
        .equivalencies
        .unwrap_or_default()
        .into_iter()
        .filter_map(assist_row_to_import)
        .collect();

    if rows.is_empty() {
        return Err(crate::commands::CommandError {
            message: "No ASSIST equivalencies found in payload".into(),
        });
    }

    let result = state
        .db
        .with_conn(|conn| Ok(import_equivalency_rows(conn, &rows)?))?;
    bump_transfer(&app, &state)?;
    Ok(result)
}
