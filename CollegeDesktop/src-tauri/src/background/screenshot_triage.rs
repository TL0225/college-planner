//! Daily scan for screenshots on Desktop and Pictures/Screenshots — import to vault inbox.

use crate::commands::documents::{import_path_to_vault, ImportVaultFileInput};
use crate::AppState;
use regex::Regex;
use std::path::{Path, PathBuf};
use std::sync::OnceLock;
use tauri::{AppHandle, Manager};
use tauri_plugin_notification::NotificationExt;

const SCAN_INTERVAL: std::time::Duration = std::time::Duration::from_secs(24 * 3600);
const SCREENSHOT_EXTENSIONS: &[&str] = &["png", "jpg", "jpeg"];

fn screenshot_name_pattern() -> &'static Regex {
    static RE: OnceLock<Regex> = OnceLock::new();
    RE.get_or_init(|| {
        Regex::new(r"^(Screen Shot \d{4}-\d{2}-\d{2}|Screenshot \d{4}-)")
            .expect("screenshot regex")
    })
}

fn is_screenshot_file(path: &Path) -> bool {
    let ext_ok = path
        .extension()
        .and_then(|e| e.to_str())
        .map(|e| SCREENSHOT_EXTENSIONS.contains(&e.to_ascii_lowercase().as_str()))
        .unwrap_or(false);
    if !ext_ok {
        return false;
    }

    let name = path.file_name().and_then(|n| n.to_str()).unwrap_or("");
    if path
        .parent()
        .and_then(|p| p.file_name())
        .and_then(|n| n.to_str())
        == Some("Screenshots")
    {
        return true;
    }
    screenshot_name_pattern().is_match(name)
}

fn scan_dirs() -> Vec<PathBuf> {
    let mut dirs = Vec::new();
    if let Some(d) = dirs::desktop_dir() {
        dirs.push(d);
    }
    if let Some(home) = dirs::home_dir() {
        dirs.push(home.join("Pictures/Screenshots"));
    }
    dirs
}

fn already_imported(state: &AppState, filename: &str) -> bool {
    state
        .db
        .with_conn(|conn| {
            let count: i64 = conn.query_row(
                "SELECT COUNT(*) FROM vault_document WHERE relative_path LIKE '%' || ?1",
                rusqlite::params![filename],
                |r| r.get(0),
            )?;
            Ok(count > 0)
        })
        .unwrap_or(false)
}

fn scan_and_import(app: &AppHandle, state: &AppState) {
    let mut imported = 0usize;

    for dir in scan_dirs() {
        if !dir.is_dir() {
            continue;
        }
        let entries = match std::fs::read_dir(&dir) {
            Ok(e) => e,
            Err(e) => {
                tracing::debug!(path = %dir.display(), error = %e, "screenshot triage skipped dir");
                continue;
            }
        };

        for entry in entries.flatten() {
            let path = entry.path();
            if !path.is_file() || !is_screenshot_file(&path) {
                continue;
            }

            let filename = path
                .file_name()
                .and_then(|n| n.to_str())
                .unwrap_or("");
            if already_imported(state, filename) {
                continue;
            }

            let input = ImportVaultFileInput {
                source_path: path.display().to_string(),
                category: Some("inbox".into()),
                title: None,
                parent_folder_id: None,
            };

            match import_path_to_vault(app, state, &input) {
                Ok(_) => {
                    imported += 1;
                    tracing::info!(path = %path.display(), "screenshot triage imported");
                }
                Err(e) => {
                    tracing::warn!(path = %path.display(), error = %e, "screenshot triage import failed");
                }
            }
        }
    }

    if imported > 0 {
        let body = format!(
            "Imported {imported} screenshot{} to vault inbox.",
            if imported == 1 { "" } else { "s" }
        );
        let _ = app
            .notification()
            .builder()
            .title("Screenshot triage")
            .body(&body)
            .show();
    }
}

pub fn spawn(app: AppHandle) {
    tauri::async_runtime::spawn(async move {
        // First scan shortly after launch, then daily.
        tokio::time::sleep(std::time::Duration::from_secs(30)).await;

        loop {
            if let Some(state) = app.try_state::<AppState>() {
                scan_and_import(&app, state.inner());
            }
            tokio::time::sleep(SCAN_INTERVAL).await;
        }
    });
}
