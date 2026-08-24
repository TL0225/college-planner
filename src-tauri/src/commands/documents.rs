use crate::commands::CmdResult;
use crate::db::DbChangeEvent;
use crate::AppState;
use aes_gcm::{
    aead::{Aead, KeyInit},
    Aes256Gcm, Nonce,
};
use base64::{engine::general_purpose::STANDARD as BASE64, Engine as _};
use chrono::Utc;
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;
use tauri::{AppHandle, Emitter, State};
use uuid::Uuid;

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct VaultDocumentDto {
    pub id: String,
    pub title: String,
    pub category: String,
    pub mime_type: String,
    pub file_size: i64,
    pub updated_at: String,
    pub relative_path: String,
    pub has_file: bool,
    pub is_starred: bool,
    pub parent_folder_id: Option<String>,
    pub is_folder: bool,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ImportVaultFileInput {
    pub source_path: String,
    pub category: Option<String>,
    pub title: Option<String>,
    pub parent_folder_id: Option<String>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct QuickLookResult {
    pub opened: bool,
    pub path: Option<String>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct QuickLookPreviewResult {
    pub mime_type: String,
    pub base64_preview: Option<String>,
    pub temp_path: Option<String>,
    pub is_encrypted: bool,
}

const VAULT_BLOB_MAGIC: &[u8] = b"COLENC1";
const PREVIEW_TEXT_MAX: usize = 512 * 1024;

fn is_encrypted_vault_blob(data: &[u8]) -> bool {
    data.len() > VAULT_BLOB_MAGIC.len() && data.starts_with(VAULT_BLOB_MAGIC)
}

fn decrypt_vault_blob(stored: &[u8], key: &[u8]) -> Option<Vec<u8>> {
    if key.len() != 32 {
        return None;
    }
    let combined = stored.get(VAULT_BLOB_MAGIC.len()..)?;
    if combined.len() < 12 + 16 {
        return None;
    }
    let cipher = Aes256Gcm::new_from_slice(key).ok()?;
    let nonce = Nonce::from_slice(&combined[..12]);
    cipher.decrypt(nonce, combined[12..].as_ref()).ok()
}

fn vault_plaintext(
    state: &AppState,
    stored: &[u8],
) -> Result<(Vec<u8>, bool), anyhow::Error> {
    if !is_encrypted_vault_blob(stored) {
        return Ok((stored.to_vec(), false));
    }
    if state.security.is_locked() {
        return Ok((vec![], true));
    }
    if let Ok(Some(key)) = state.security.get_secret("vault", "masterKey") {
        if let Some(plain) = decrypt_vault_blob(stored, &key) {
            return Ok((plain, true));
        }
    }
    Ok((vec![], true))
}

fn write_preview_temp(
    state: &AppState,
    doc_id: &str,
    display_name: &str,
    bytes: &[u8],
) -> Result<PathBuf, anyhow::Error> {
    let preview_dir = state.paths.cache_dir.join("preview");
    fs::create_dir_all(&preview_dir)?;
    let safe = sanitize_filename(display_name);
    let stem = if safe.is_empty() { "preview".into() } else { safe };
    let short_id = doc_id.chars().take(8).collect::<String>();
    let temp = preview_dir.join(format!("{short_id}-{stem}"));
    fs::write(&temp, bytes)?;
    Ok(temp)
}

fn text_mime_preview(mime: &str, bytes: &[u8]) -> Option<String> {
    let lower = mime.to_ascii_lowercase();
    let is_text = lower.starts_with("text/")
        || lower.contains("json")
        || lower.contains("csv")
        || lower.contains("javascript");
    if !is_text || bytes.len() > PREVIEW_TEXT_MAX {
        return None;
    }
    Some(BASE64.encode(bytes))
}

fn emit_vault_change(app: &AppHandle, state: &AppState) -> CmdResult<()> {
    let rev = state.db.bump_revision("vault")?;
    let _ = app.emit(
        "db:change",
        DbChangeEvent {
            domain: "vault".to_string(),
            revision: rev,
        },
    );
    Ok(())
}

fn guess_mime(path: &Path) -> &'static str {
    match path
        .extension()
        .and_then(|e| e.to_str())
        .unwrap_or("")
        .to_ascii_lowercase()
        .as_str()
    {
        "pdf" => "application/pdf",
        "png" => "image/png",
        "jpg" | "jpeg" => "image/jpeg",
        "gif" => "image/gif",
        "webp" => "image/webp",
        "txt" | "md" => "text/plain",
        "doc" | "docx" => "application/msword",
        "xls" | "xlsx" => "application/vnd.ms-excel",
        "csv" => "text/csv",
        "json" => "application/json",
        "html" | "htm" => "text/html",
        _ => "application/octet-stream",
    }
}

fn sanitize_filename(name: &str) -> String {
    let cleaned: String = name
        .chars()
        .map(|c| match c {
            '/' | '\\' | ':' | '*' | '?' | '"' | '<' | '>' | '|' => '_',
            c if c.is_control() => '_',
            c => c,
        })
        .collect();
    let trimmed = cleaned.trim().trim_matches('.');
    if trimmed.is_empty() {
        "document".into()
    } else {
        trimmed.chars().take(120).collect()
    }
}

fn validate_parent_folder(
    conn: &rusqlite::Connection,
    parent_folder_id: Option<&str>,
) -> Result<(), rusqlite::Error> {
    let Some(parent_id) = parent_folder_id.filter(|id| !id.is_empty()) else {
        return Ok(());
    };
    let is_folder: i32 = conn.query_row(
        "SELECT is_folder FROM vault_document WHERE id = ?1",
        rusqlite::params![parent_id],
        |r| r.get(0),
    )?;
    if is_folder == 0 {
        return Err(rusqlite::Error::InvalidParameterName(
            "parent is not a folder".into(),
        ));
    }
    Ok(())
}

fn is_descendant_folder(
    conn: &rusqlite::Connection,
    ancestor_id: &str,
    candidate_id: &str,
) -> Result<bool, rusqlite::Error> {
    let mut current = Some(candidate_id.to_string());
    while let Some(id) = current {
        if id == ancestor_id {
            return Ok(true);
        }
        current = conn
            .query_row(
                "SELECT parent_folder_id FROM vault_document WHERE id = ?1",
                rusqlite::params![id],
                |r| r.get::<_, Option<String>>(0),
            )
            .ok()
            .flatten()
            .filter(|p| !p.is_empty());
    }
    Ok(false)
}

fn row_to_dto(r: &rusqlite::Row<'_>) -> rusqlite::Result<VaultDocumentDto> {
    let relative_path: String = r.get(6)?;
    let is_starred: i32 = r.get(7)?;
    let parent_folder_id: Option<String> = r.get(8)?;
    let is_folder: i32 = r.get(9)?;
    Ok(VaultDocumentDto {
        id: r.get(0)?,
        title: r.get(1)?,
        category: r.get(2)?,
        mime_type: r.get(3)?,
        file_size: r.get(4)?,
        updated_at: r.get(5)?,
        has_file: !relative_path.is_empty(),
        relative_path,
        is_starred: is_starred != 0,
        parent_folder_id: parent_folder_id.filter(|p| !p.is_empty()),
        is_folder: is_folder != 0,
    })
}

#[tauri::command]
pub fn documents_list_vault(state: State<'_, AppState>) -> CmdResult<Vec<VaultDocumentDto>> {
    state
        .db
        .with_conn(|conn| {
            let mut stmt = conn.prepare(
                "SELECT id, title, category, mime_type, file_size, updated_at, relative_path, is_starred,
                        parent_folder_id, is_folder
                 FROM vault_document ORDER BY is_folder DESC, sort_order ASC, title COLLATE NOCASE ASC, updated_at DESC LIMIT 500",
            )?;
            let rows = stmt
                .query_map([], row_to_dto)?
                .collect::<Result<Vec<_>, _>>()?;
            Ok(rows)
        })
        .map_err(Into::into)
}

/// Copy a file on disk into the vault and insert a `vault_document` row.
pub fn import_path_to_vault(
    app: &AppHandle,
    state: &AppState,
    input: &ImportVaultFileInput,
) -> Result<String, anyhow::Error> {
    let source = PathBuf::from(&input.source_path);
    if !source.is_file() {
        return Err(anyhow::anyhow!("Source path is not a file"));
    }

    state.db.with_conn(|conn| {
        validate_parent_folder(conn, input.parent_folder_id.as_deref())?;
        Ok(())
    })?;

    let original_name = source
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or("document");
    let title = input
        .title
        .as_ref()
        .filter(|t| !t.trim().is_empty())
        .cloned()
        .unwrap_or_else(|| {
            Path::new(original_name)
                .file_stem()
                .and_then(|s| s.to_str())
                .unwrap_or(original_name)
                .to_string()
        });
    let category = input
        .category
        .clone()
        .unwrap_or_else(|| "general".into());
    let mime = guess_mime(&source);
    let meta = fs::metadata(&source)?;
    let file_size = meta.len() as i64;

    let id = Uuid::new_v4().to_string();
    let safe_name = sanitize_filename(original_name);
    let relative = format!("{}_{}", &id[..8], safe_name);
    let dest = state.paths.vault_dir.join(&relative);
    fs::create_dir_all(&state.paths.vault_dir)?;
    fs::copy(&source, &dest)?;

    let now = Utc::now().to_rfc3339();
    state.db.with_conn(|conn| {
        conn.execute(
            "INSERT INTO vault_document
             (id, title, relative_path, mime_type, category, parent_folder_id, course_id,
              tags_json, file_size, created_at, updated_at, sort_order, is_folder)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, NULL, '[]', ?7, ?8, ?8, 0, 0)",
            rusqlite::params![
                id,
                title,
                relative,
                mime,
                category,
                input.parent_folder_id,
                file_size,
                now
            ],
        )?;
        Ok(())
    })?;
    emit_vault_change(app, state).map_err(|e| anyhow::anyhow!(e.message))?;
    Ok(id)
}

#[tauri::command]
pub fn documents_import_file(
    app: AppHandle,
    state: State<'_, AppState>,
    input: ImportVaultFileInput,
) -> CmdResult<String> {
    import_path_to_vault(&app, &state, &input).map_err(Into::into)
}

#[tauri::command]
pub fn documents_create_folder(
    app: AppHandle,
    state: State<'_, AppState>,
    name: String,
    parent_folder_id: Option<String>,
) -> CmdResult<String> {
    let title = name.trim();
    if title.is_empty() {
        return Err(anyhow::anyhow!("Folder name is required").into());
    }

    state.db.with_conn(|conn| {
        validate_parent_folder(conn, parent_folder_id.as_deref())?;
        Ok(())
    })?;

    let id = Uuid::new_v4().to_string();
    let now = Utc::now().to_rfc3339();
    state.db.with_conn(|conn| {
        conn.execute(
            "INSERT INTO vault_document
             (id, title, relative_path, mime_type, category, parent_folder_id, course_id,
              tags_json, file_size, created_at, updated_at, sort_order, is_folder)
             VALUES (?1, ?2, '', 'inode/directory', 'general', ?3, NULL, '[]', 0, ?4, ?4, 0, 1)",
            rusqlite::params![id, title, parent_folder_id, now],
        )?;
        Ok(())
    })?;
    emit_vault_change(&app, &state)?;
    Ok(id)
}

#[tauri::command]
pub fn documents_move_vault_item(
    app: AppHandle,
    state: State<'_, AppState>,
    id: String,
    parent_folder_id: Option<String>,
) -> CmdResult<()> {
    if parent_folder_id.as_deref() == Some(id.as_str()) {
        return Err(anyhow::anyhow!("Cannot move an item into itself").into());
    }

    state.db.with_conn(|conn| {
        validate_parent_folder(conn, parent_folder_id.as_deref())?;

        let is_folder: i32 = conn.query_row(
            "SELECT is_folder FROM vault_document WHERE id = ?1",
            rusqlite::params![id],
            |r| r.get(0),
        )?;

        if let Some(parent_id) = parent_folder_id.as_deref().filter(|p| !p.is_empty()) {
            if is_folder != 0 && is_descendant_folder(conn, &id, parent_id)? {
                return Err(rusqlite::Error::InvalidParameterName(
                    "cannot move folder into its descendant".into(),
                )
                .into());
            }
        }

        let now = Utc::now().to_rfc3339();
        conn.execute(
            "UPDATE vault_document SET parent_folder_id = ?1, updated_at = ?2 WHERE id = ?3",
            rusqlite::params![parent_folder_id, now, id],
        )?;
        Ok(())
    })?;
    emit_vault_change(&app, &state)?;
    Ok(())
}

#[tauri::command]
pub fn documents_rename_vault_item(
    app: AppHandle,
    state: State<'_, AppState>,
    id: String,
    title: String,
) -> CmdResult<()> {
    let trimmed = title.trim();
    if trimmed.is_empty() {
        return Err(anyhow::anyhow!("Title is required").into());
    }
    let now = Utc::now().to_rfc3339();
    state.db.with_conn(|conn| {
        conn.execute(
            "UPDATE vault_document SET title = ?1, updated_at = ?2 WHERE id = ?3",
            rusqlite::params![trimmed, now, id],
        )?;
        Ok(())
    })?;
    emit_vault_change(&app, &state)?;
    Ok(())
}

#[tauri::command]
pub fn documents_quick_look(
    state: State<'_, AppState>,
    id: String,
) -> CmdResult<QuickLookResult> {
    let relative: Option<String> = state.db.with_conn(|conn| {
        match conn.query_row(
            "SELECT relative_path FROM vault_document WHERE id = ?1 AND is_folder = 0",
            rusqlite::params![id],
            |r| r.get::<_, String>(0),
        ) {
            Ok(path) => Ok(Some(path)),
            Err(rusqlite::Error::QueryReturnedNoRows) => Ok(None),
            Err(e) => Err(e.into()),
        }
    })?;
    let Some(rel) = relative.filter(|r| !r.is_empty()) else {
        return Ok(QuickLookResult {
            opened: false,
            path: None,
        });
    };
    let abs = state.paths.vault_dir.join(rel);
    if !abs.is_file() {
        return Ok(QuickLookResult {
            opened: false,
            path: None,
        });
    }
    let path_str = abs.display().to_string();

    #[cfg(target_os = "macos")]
    {
        let opened = Command::new("qlmanage")
            .args(["-p", &path_str])
            .spawn()
            .map(|_| true)
            .unwrap_or(false);
        if opened {
            return Ok(QuickLookResult {
                opened: true,
                path: Some(path_str),
            });
        }
    }

    Ok(QuickLookResult {
        opened: false,
        path: Some(path_str),
    })
}

#[tauri::command]
pub fn documents_quick_look_preview(
    state: State<'_, AppState>,
    id: String,
) -> CmdResult<QuickLookPreviewResult> {
    let row: Option<(String, String, String)> = state.db.with_conn(|conn| {
        match conn.query_row(
            "SELECT relative_path, mime_type, title FROM vault_document WHERE id = ?1 AND is_folder = 0",
            rusqlite::params![id],
            |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)),
        ) {
            Ok(v) => Ok(Some(v)),
            Err(rusqlite::Error::QueryReturnedNoRows) => Ok(None),
            Err(e) => Err(e.into()),
        }
    })?;
    let Some((rel, mime_type, title)) = row else {
        return Ok(QuickLookPreviewResult {
            mime_type: "application/octet-stream".into(),
            base64_preview: None,
            temp_path: None,
            is_encrypted: false,
        });
    };
    if rel.is_empty() {
        return Ok(QuickLookPreviewResult {
            mime_type: mime_type.clone(),
            base64_preview: None,
            temp_path: None,
            is_encrypted: false,
        });
    }
    let abs = state.paths.vault_dir.join(&rel);
    if !abs.is_file() {
        return Ok(QuickLookPreviewResult {
            mime_type: mime_type.clone(),
            base64_preview: None,
            temp_path: None,
            is_encrypted: false,
        });
    }

    let stored = fs::read(&abs).map_err(anyhow::Error::from)?;
    let (plaintext, was_encrypted) = vault_plaintext(state.inner(), &stored)?;
    if was_encrypted && plaintext.is_empty() {
        return Ok(QuickLookPreviewResult {
            mime_type: mime_type.clone(),
            base64_preview: None,
            temp_path: None,
            is_encrypted: true,
        });
    }

    let mime = if mime_type.is_empty() {
        guess_mime(&abs).to_string()
    } else {
        mime_type
    };
    let base64_preview = text_mime_preview(&mime, &plaintext);
    let temp_path = if base64_preview.is_none() {
        let temp = write_preview_temp(state.inner(), &id, &title, &plaintext)?;
        Some(temp.display().to_string())
    } else {
        None
    };

    Ok(QuickLookPreviewResult {
        mime_type: mime,
        base64_preview,
        temp_path,
        is_encrypted: was_encrypted,
    })
}

#[tauri::command]
pub fn documents_resolve_path(
    state: State<'_, AppState>,
    id: String,
) -> CmdResult<Option<String>> {
    let relative: Option<String> = state.db.with_conn(|conn| {
        match conn.query_row(
            "SELECT relative_path FROM vault_document WHERE id = ?1 AND is_folder = 0",
            rusqlite::params![id],
            |r| r.get::<_, String>(0),
        ) {
            Ok(path) => Ok(Some(path)),
            Err(rusqlite::Error::QueryReturnedNoRows) => Ok(None),
            Err(e) => Err(e.into()),
        }
    })?;
    let Some(rel) = relative.filter(|r| !r.is_empty()) else {
        return Ok(None);
    };
    let abs = state.paths.vault_dir.join(rel);
    if abs.is_file() {
        Ok(Some(abs.display().to_string()))
    } else {
        Ok(None)
    }
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UpdateVaultDocInput {
    pub id: String,
    pub title: Option<String>,
    pub category: Option<String>,
    pub is_starred: Option<bool>,
}

#[tauri::command]
pub fn documents_update_vault_doc(
    app: AppHandle,
    state: State<'_, AppState>,
    input: UpdateVaultDocInput,
) -> CmdResult<()> {
    let now = Utc::now().to_rfc3339();
    state.db.with_conn(|conn| {
        if let Some(title) = input.title.filter(|t| !t.trim().is_empty()) {
            conn.execute(
                "UPDATE vault_document SET title = ?1, updated_at = ?2 WHERE id = ?3",
                rusqlite::params![title.trim(), now, input.id],
            )?;
        }
        if let Some(category) = input.category.filter(|c| !c.trim().is_empty()) {
            conn.execute(
                "UPDATE vault_document SET category = ?1, updated_at = ?2 WHERE id = ?3",
                rusqlite::params![category.trim(), now, input.id],
            )?;
        }
        if let Some(is_starred) = input.is_starred {
            conn.execute(
                "UPDATE vault_document SET is_starred = ?1, updated_at = ?2 WHERE id = ?3",
                rusqlite::params![if is_starred { 1 } else { 0 }, now, input.id],
            )?;
        }
        Ok(())
    })?;
    emit_vault_change(&app, &state)?;
    Ok(())
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct WatchedFolderDto {
    pub id: String,
    pub path: String,
    pub added_at: String,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UpsertWatchedFolderInput {
    pub id: Option<String>,
    pub path: String,
}

#[tauri::command]
pub fn documents_list_watched_folders(state: State<'_, AppState>) -> CmdResult<Vec<WatchedFolderDto>> {
    state
        .db
        .with_conn(|conn| {
            let mut stmt = conn.prepare(
                "SELECT id, path, added_at FROM watched_folder ORDER BY added_at DESC",
            )?;
            let rows = stmt.query_map([], |r| {
                Ok(WatchedFolderDto {
                    id: r.get(0)?,
                    path: r.get(1)?,
                    added_at: r.get(2)?,
                })
            })?;
            Ok(rows.filter_map(|r| r.ok()).collect())
        })
        .map_err(Into::into)
}

#[tauri::command]
pub fn documents_upsert_watched_folder(
    app: AppHandle,
    state: State<'_, AppState>,
    input: UpsertWatchedFolderInput,
) -> CmdResult<String> {
    let path = input.path.trim();
    if path.is_empty() {
        return Err(anyhow::anyhow!("Folder path is required").into());
    }
    let folder_id = input
        .id
        .filter(|s| !s.trim().is_empty())
        .unwrap_or_else(|| Uuid::new_v4().to_string());
    let now = Utc::now().to_rfc3339();
    state
        .db
        .with_conn(|conn| {
            conn.execute(
                "INSERT OR REPLACE INTO watched_folder (id, path, bookmark_data, added_at)
                 VALUES (?1, ?2, NULL, ?3)",
                rusqlite::params![folder_id, path, now],
            )?;
            Ok(())
        })?;
    emit_vault_change(&app, &state)?;
    Ok(folder_id)
}

#[tauri::command]
pub fn documents_delete_watched_folder(
    app: AppHandle,
    state: State<'_, AppState>,
    id: String,
) -> CmdResult<()> {
    state
        .db
        .with_conn(|conn| {
            conn.execute("DELETE FROM watched_folder WHERE id = ?1", rusqlite::params![id])?;
            Ok(())
        })?;
    emit_vault_change(&app, &state)?;
    Ok(())
}
