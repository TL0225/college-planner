//! Portable backup / restore of College.sqlite (+ vault files for cross-OS moves).

use crate::commands::CmdResult;
use crate::db::AppDb;
use crate::AppState;
use chrono::Utc;
use serde::Serialize;
use std::fs;
use std::io::{Read, Write};
use std::path::{Path, PathBuf};
use tauri::State;

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct BackupEntry {
    pub name: String,
    pub path: String,
    pub size_bytes: u64,
    pub modified_at: String,
    /// True when backup includes Vault/ alongside the DB (portable package).
    pub includes_vault: bool,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct BackupRestoreResult {
    pub pending_path: String,
    pub safety_backup: Option<String>,
    pub needs_restart: bool,
}

fn pending_restore_path(db_path: &Path) -> PathBuf {
    db_path.with_extension("sqlite.pending-restore")
}

fn strip_sidecar(db_path: &Path) {
    let wal = PathBuf::from(format!("{}-wal", db_path.display()));
    let shm = PathBuf::from(format!("{}-shm", db_path.display()));
    let _ = fs::remove_file(wal);
    let _ = fs::remove_file(shm);
}

/// Apply a pending restore file before opening the live DB (called from app setup).
pub fn apply_pending_restore_if_any(db_path: &Path, backups_dir: &Path) -> anyhow::Result<bool> {
    let pending = pending_restore_path(db_path);
    if !pending.exists() {
        return Ok(false);
    }
    fs::create_dir_all(backups_dir)?;
    if db_path.exists() {
        let stamp = Utc::now().format("%Y%m%d-%H%M%S");
        let safety = backups_dir.join(format!("pre-restore-{stamp}.sqlite"));
        fs::copy(db_path, &safety)?;
    }
    strip_sidecar(db_path);
    fs::copy(&pending, db_path)?;
    let _ = fs::remove_file(&pending);
    strip_sidecar(db_path);

    // Restore vault if a sibling package folder exists.
    let vault_pkg = pending.with_extension("sqlite.pending-vault");
    if vault_pkg.is_dir() {
        let vault_dest = db_path
            .parent()
            .map(|p| p.join("Vault"))
            .unwrap_or_else(|| PathBuf::from("Vault"));
        if vault_dest.exists() {
            let _ = fs::remove_dir_all(&vault_dest);
        }
        copy_dir_recursive(&vault_pkg, &vault_dest)?;
        let _ = fs::remove_dir_all(&vault_pkg);
    }
    Ok(true)
}

fn copy_dir_recursive(src: &Path, dst: &Path) -> anyhow::Result<()> {
    fs::create_dir_all(dst)?;
    for entry in fs::read_dir(src)? {
        let entry = entry?;
        let ty = entry.file_type()?;
        let to = dst.join(entry.file_name());
        if ty.is_dir() {
            copy_dir_recursive(&entry.path(), &to)?;
        } else {
            fs::copy(entry.path(), to)?;
        }
    }
    Ok(())
}

/// Checkpoint WAL and copy the live College DB into `backups_dir`.
/// Also copies Vault/ into a sibling folder for portable Win↔Mac restores.
pub fn backup_college_db(
    db: &AppDb,
    db_path: &Path,
    vault_dir: &Path,
    backups_dir: &Path,
) -> anyhow::Result<BackupEntry> {
    fs::create_dir_all(backups_dir)?;
    let stamp = Utc::now().format("%Y%m%d-%H%M%S");
    let name = format!("college-{stamp}.sqlite");
    let dest = backups_dir.join(&name);
    let _ = db.with_conn(|conn| {
        // Prefer online backup API for a consistent snapshot across OS.
        let mut dst_conn = rusqlite::Connection::open(&dest)?;
        {
            let backup = rusqlite::backup::Backup::new(conn, &mut dst_conn)?;
            backup.run_to_completion(100, std::time::Duration::from_millis(16), None)?;
        }
        Ok(())
    })?;
    // Fallback if backup API path somehow empty.
    if !dest.exists() || fs::metadata(&dest)?.len() == 0 {
        let _ = db.with_conn(|conn| {
            let _ = conn.execute_batch("PRAGMA wal_checkpoint(TRUNCATE);");
            Ok(())
        })?;
        fs::copy(db_path, &dest)?;
    }

    let mut includes_vault = false;
    if vault_dir.is_dir() {
        let vault_dest = backups_dir.join(format!("college-{stamp}.vault"));
        copy_dir_recursive(vault_dir, &vault_dest)?;
        includes_vault = true;
        // Write a tiny manifest for restore tooling.
        let manifest = backups_dir.join(format!("college-{stamp}.portable.json"));
        let body = serde_json::json!({
            "format": "college-portable-v1",
            "db": name,
            "vault": format!("college-{stamp}.vault"),
            "createdAt": Utc::now().to_rfc3339(),
        });
        let mut f = fs::File::create(manifest)?;
        f.write_all(serde_json::to_string_pretty(&body)?.as_bytes())?;
    }

    let meta = fs::metadata(&dest)?;
    Ok(BackupEntry {
        name,
        path: dest.display().to_string(),
        size_bytes: meta.len(),
        modified_at: Utc::now().to_rfc3339(),
        includes_vault,
    })
}

#[tauri::command]
pub fn backup_create(state: State<'_, AppState>) -> CmdResult<BackupEntry> {
    backup_college_db(
        &state.db,
        &state.paths.college_db_path,
        &state.paths.vault_dir,
        &state.paths.backups_dir,
    )
    .map_err(Into::into)
}

#[tauri::command]
pub fn backup_list(state: State<'_, AppState>) -> CmdResult<Vec<BackupEntry>> {
    fs::create_dir_all(&state.paths.backups_dir).map_err(anyhow::Error::from)?;
    let mut out = Vec::new();
    for entry in fs::read_dir(&state.paths.backups_dir).map_err(anyhow::Error::from)? {
        let entry = entry.map_err(anyhow::Error::from)?;
        let path = entry.path();
        if path.extension().and_then(|e| e.to_str()) != Some("sqlite") {
            continue;
        }
        let meta = entry.metadata().map_err(anyhow::Error::from)?;
        let stem = path.file_stem().and_then(|s| s.to_str()).unwrap_or("");
        let vault_sib = state.paths.backups_dir.join(format!("{stem}.vault"));
        let modified = meta
            .modified()
            .ok()
            .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
            .map(|d| {
                chrono::DateTime::<Utc>::from_timestamp(d.as_secs() as i64, 0)
                    .map(|dt| dt.to_rfc3339())
                    .unwrap_or_default()
            })
            .unwrap_or_default();
        out.push(BackupEntry {
            name: entry.file_name().to_string_lossy().to_string(),
            path: path.display().to_string(),
            size_bytes: meta.len(),
            modified_at: modified,
            includes_vault: vault_sib.is_dir(),
        });
    }
    out.sort_by(|a, b| b.name.cmp(&a.name));
    Ok(out)
}

/// Stage a restore: copy backup to `*.pending-restore` and ask the UI to relaunch.
#[tauri::command]
pub fn backup_restore(state: State<'_, AppState>, path: String) -> CmdResult<BackupRestoreResult> {
    let source = PathBuf::from(path.trim());
    if !source.exists() {
        return Err(anyhow::anyhow!("Backup file not found").into());
    }
    if source.extension().and_then(|e| e.to_str()) != Some("sqlite") {
        return Err(anyhow::anyhow!("Restore source must be a .sqlite backup").into());
    }
    let backups = state
        .paths
        .backups_dir
        .canonicalize()
        .unwrap_or_else(|_| state.paths.backups_dir.clone());
    let canon = source
        .canonicalize()
        .map_err(|e| anyhow::anyhow!("Invalid backup path: {e}"))?;
    if !canon.starts_with(&backups) {
        return Err(anyhow::anyhow!("Backup must live inside the Backups folder").into());
    }

    fs::create_dir_all(&state.paths.backups_dir).map_err(anyhow::Error::from)?;
    let mut safety_backup = None;
    if state.paths.college_db_path.exists() {
        let stamp = Utc::now().format("%Y%m%d-%H%M%S");
        let safety_name = format!("pre-restore-{stamp}.sqlite");
        let safety_path = state.paths.backups_dir.join(&safety_name);
        let _ = state.db.with_conn(|conn| {
            let _ = conn.execute_batch("PRAGMA wal_checkpoint(TRUNCATE);");
            Ok(())
        });
        fs::copy(&state.paths.college_db_path, &safety_path).map_err(anyhow::Error::from)?;
        safety_backup = Some(safety_path.display().to_string());
    }

    let pending = pending_restore_path(&state.paths.college_db_path);
    fs::copy(&canon, &pending).map_err(anyhow::Error::from)?;

    // Stage vault package if present next to the sqlite backup.
    let stem = canon.file_stem().and_then(|s| s.to_str()).unwrap_or("");
    let vault_src = state.paths.backups_dir.join(format!("{stem}.vault"));
    if vault_src.is_dir() {
        let vault_pending = pending.with_extension("sqlite.pending-vault");
        if vault_pending.exists() {
            let _ = fs::remove_dir_all(&vault_pending);
        }
        copy_dir_recursive(&vault_src, &vault_pending).map_err(anyhow::Error::from)?;
    }

    Ok(BackupRestoreResult {
        pending_path: pending.display().to_string(),
        safety_backup,
        needs_restart: true,
    })
}

#[allow(dead_code)]
fn read_portable_manifest(path: &Path) -> Option<serde_json::Value> {
    let mut buf = String::new();
    fs::File::open(path).ok()?.read_to_string(&mut buf).ok()?;
    serde_json::from_str(&buf).ok()
}
