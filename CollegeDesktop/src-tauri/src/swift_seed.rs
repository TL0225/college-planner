//! One-shot seed: copy Swift College workspace into Tauri's dedicated data root.
//! No Settings UI — runs automatically when the Tauri DB is missing / empty.

use crate::commands::platform_import::{
    import_swift_workspace_inner, ImportSwiftWorkspaceInput, ImportSwiftWorkspaceReport,
};
use crate::db::AppDb;
use crate::paths::{
    AppPaths, swift_college_db_path, swift_document_vault_path, swift_finance_db_path,
};
use anyhow::Result;
use std::fs;
use std::path::{Path, PathBuf};

fn seed_marker(paths: &AppPaths) -> PathBuf {
    paths.root.join(".swift-seed-done")
}

fn profile_count(db: &AppDb) -> Result<i64> {
    db.with_conn(|conn| {
        let n: i64 = conn
            .query_row("SELECT COUNT(*) FROM profile", [], |r| r.get(0))
            .unwrap_or(0);
        Ok(n)
    })
}

fn copy_dir_contents(src: &Path, dest: &Path) -> Result<u64> {
    if !src.is_dir() {
        return Ok(0);
    }
    fs::create_dir_all(dest)?;
    let mut n = 0u64;
    for entry in fs::read_dir(src)? {
        let entry = entry?;
        let from = entry.path();
        let to = dest.join(entry.file_name());
        if from.is_file() {
            if !to.exists() {
                fs::copy(&from, &to)?;
                n += 1;
            }
        } else if from.is_dir() {
            n += copy_dir_contents(&from, &to)?;
        }
    }
    Ok(n)
}

/// If Tauri has no profile rows yet and a Swift DB exists, import once into the Tauri store.
pub fn seed_from_swift_if_needed(
    db: &AppDb,
    paths: &AppPaths,
) -> Result<Option<ImportSwiftWorkspaceReport>> {
    let marker = seed_marker(paths);
    if marker.exists() {
        return Ok(None);
    }

    let swift_db = match swift_college_db_path() {
        Some(p) if p.exists() => p,
        _ => {
            let _ = fs::write(&marker, b"no-swift-db");
            return Ok(None);
        }
    };

    // Already has user data — don't overwrite; just mark done.
    if profile_count(db).unwrap_or(0) > 0 {
        let _ = fs::write(&marker, b"already-populated");
        return Ok(None);
    }

    let report = import_swift_workspace_inner(
        db,
        paths,
        ImportSwiftWorkspaceInput {
            swift_college_db: Some(swift_db.display().to_string()),
            swift_finance_db: swift_finance_db_path()
                .filter(|p| p.exists())
                .map(|p| p.display().to_string()),
            domains: None,
        },
    )?;

    if let Some(vault) = swift_document_vault_path() {
        let _ = copy_dir_contents(&vault, &paths.vault_dir);
    }

    let _ = fs::write(
        &marker,
        format!("ok total_rows={}", report.total_rows).as_bytes(),
    );
    Ok(Some(report))
}

/// Force a fresh copy of Swift → Tauri (used by CLI / one-shot ops). Ignores the seed marker.
pub fn copy_swift_workspace_now(
    db: &AppDb,
    paths: &AppPaths,
) -> Result<ImportSwiftWorkspaceReport> {
    let _ = fs::remove_file(seed_marker(paths));
    let swift_db = swift_college_db_path()
        .filter(|p| p.exists())
        .ok_or_else(|| anyhow::anyhow!("Swift College.sqlite not found"))?;

    let report = import_swift_workspace_inner(
        db,
        paths,
        ImportSwiftWorkspaceInput {
            swift_college_db: Some(swift_db.display().to_string()),
            swift_finance_db: swift_finance_db_path()
                .filter(|p| p.exists())
                .map(|p| p.display().to_string()),
            domains: None,
        },
    )?;

    if let Some(vault) = swift_document_vault_path() {
        let _ = copy_dir_contents(&vault, &paths.vault_dir);
    }

    let _ = fs::write(
        seed_marker(paths),
        format!("ok total_rows={}", report.total_rows).as_bytes(),
    );
    Ok(report)
}
