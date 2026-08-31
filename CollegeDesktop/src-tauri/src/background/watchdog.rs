//! Filesystem watchdog — auto-import academic files from watched folders.

use crate::commands::documents::{import_path_to_vault, ImportVaultFileInput};
use crate::AppState;
use chrono::Utc;
use notify_debouncer_full::{new_debouncer, DebounceEventResult, Debouncer, FileIdMap};
use notify::{EventKind, RecursiveMode};
use parking_lot::RwLock;
use std::path::{Path, PathBuf};
use std::sync::{Arc, OnceLock};
use std::time::Duration;
use tauri::{AppHandle, Manager};
use tauri_plugin_notification::NotificationExt;

const WATCH_EXTENSIONS: &[&str] = &["pdf", "docx", "doc", "jpg", "jpeg", "png"];

#[derive(Debug, Clone, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct WatchdogStatus {
    pub is_watching: bool,
    pub watched_count: usize,
    pub last_detected_path: Option<String>,
    pub last_detected_at: Option<String>,
}

static STATUS: OnceLock<Arc<RwLock<WatchdogStatus>>> = OnceLock::new();

fn status_lock() -> Arc<RwLock<WatchdogStatus>> {
    STATUS
        .get_or_init(|| {
            Arc::new(RwLock::new(WatchdogStatus {
                is_watching: false,
                watched_count: 0,
                last_detected_path: None,
                last_detected_at: None,
            }))
        })
        .clone()
}

pub fn status_snapshot() -> WatchdogStatus {
    status_lock().read().clone()
}

fn is_watchable(path: &Path) -> bool {
    path.extension()
        .and_then(|e| e.to_str())
        .map(|e| WATCH_EXTENSIONS.contains(&e.to_ascii_lowercase().as_str()))
        .unwrap_or(false)
}

#[cfg(target_os = "macos")]
fn icloud_college_folder() -> Option<PathBuf> {
    dirs::home_dir().map(|home| {
        home.join("Library/Mobile Documents/com~apple~CloudDocs/College")
    })
}

#[cfg(not(target_os = "macos"))]
fn icloud_college_folder() -> Option<PathBuf> {
    None
}

fn load_watched_paths(state: &AppState) -> Vec<PathBuf> {
    let from_db: Vec<String> = state
        .db
        .with_conn(|conn| {
            let mut stmt =
                conn.prepare("SELECT path FROM watched_folder ORDER BY added_at DESC")?;
            let rows = stmt
                .query_map([], |r| r.get::<_, String>(0))?
                .collect::<Result<Vec<_>, _>>()?;
            Ok(rows)
        })
        .unwrap_or_default();

    // Opt-in only: do not watch Downloads/Desktop by default (production privacy + I/O).
    let mut paths: Vec<PathBuf> = from_db.into_iter().map(PathBuf::from).collect();

    if let Some(cloud) = icloud_college_folder() {
        if cloud.is_dir() && !paths.iter().any(|p| p == &cloud) {
            paths.push(cloud);
        }
    }

    paths
}

fn record_detection(path: &Path) {
    let lock = status_lock();
    let mut status = lock.write();
    status.last_detected_path = Some(path.display().to_string());
    status.last_detected_at = Some(Utc::now().to_rfc3339());
}

fn send_notification(app: &AppHandle, title: &str, body: &str) {
    let _ = app
        .notification()
        .builder()
        .title(title)
        .body(body)
        .show();
}

fn handle_new_file(app: &AppHandle, state: &AppState, path: PathBuf) {
    if !is_watchable(&path) || !path.is_file() {
        return;
    }

    record_detection(&path);

    let input = ImportVaultFileInput {
        source_path: path.display().to_string(),
        category: Some("general".into()),
        title: None,
        parent_folder_id: None,
    };

    match import_path_to_vault(app, state, &input) {
        Ok(id) => {
            tracing::info!(path = %path.display(), vault_id = %id, "watchdog imported file");
            send_notification(
                app,
                "Document imported",
                &format!("{} added to your vault.", path.file_name().and_then(|n| n.to_str()).unwrap_or("File")),
            );
        }
        Err(e) => {
            tracing::warn!(path = %path.display(), error = %e, "watchdog import failed");
        }
    }
}

pub fn spawn(app: AppHandle) {
    let state = match app.try_state::<AppState>() {
        Some(s) => s.inner().clone(),
        None => {
            tracing::warn!("watchdog skipped: AppState unavailable");
            return;
        }
    };

    let paths = load_watched_paths(&state);
    let existing: Vec<PathBuf> = paths.iter().filter(|p| p.is_dir()).cloned().collect();
    let watched_count = existing.len();

    {
        let lock = status_lock();
        let mut status = lock.write();
        status.watched_count = watched_count;
        status.is_watching = !existing.is_empty();
    }

    if existing.is_empty() {
        tracing::info!("watchdog: no directories to watch");
        return;
    }

    let app_cb = app.clone();
    let state_cb = state.clone();

    std::thread::spawn(move || {
        let handler = move |result: DebounceEventResult| {
            let Ok(events) = result else {
                tracing::warn!("watchdog debouncer error");
                return;
            };
            for event in events {
                match event.kind {
                    EventKind::Create(_) | EventKind::Modify(_) => {}
                    _ => continue,
                }
                for path in &event.paths {
                    if path.is_file() {
                        handle_new_file(&app_cb, &state_cb, path.clone());
                    }
                }
            }
        };

        let mut debouncer: Debouncer<_, FileIdMap> =
            match new_debouncer(Duration::from_secs(2), None, handler) {
                Ok(d) => d,
                Err(e) => {
                    tracing::error!(error = %e, "watchdog failed to create debouncer");
                    status_lock().write().is_watching = false;
                    return;
                }
            };

        for path in &existing {
            if let Err(e) = debouncer.watch(path, RecursiveMode::Recursive) {
                tracing::warn!(path = %path.display(), error = %e, "watchdog failed to watch path");
            }
        }

        tracing::info!(count = existing.len(), "watchdog started watching folders");
        status_lock().write().is_watching = true;

        loop {
            std::thread::sleep(Duration::from_secs(3600));
        }
    });
}
