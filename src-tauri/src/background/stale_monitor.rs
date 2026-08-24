//! Daily scan for vault documents older than the stale threshold.

use crate::db::DbChangeEvent;
use crate::AppState;
use chrono::Utc;
use tauri::{AppHandle, Emitter, Manager};
use tauri_plugin_notification::NotificationExt;

const SCAN_INTERVAL: std::time::Duration = std::time::Duration::from_secs(24 * 3600);

fn stale_threshold_days(state: &AppState) -> i64 {
    state
        .db
        .get_setting("documents.staleThresholdDays")
        .ok()
        .flatten()
        .and_then(|v| v.parse().ok())
        .unwrap_or(7)
        .max(1)
}

fn scan_vault_stale(app: &AppHandle, state: &AppState) {
    let threshold_days = stale_threshold_days(state);
    let cutoff = (Utc::now() - chrono::Duration::days(threshold_days)).to_rfc3339();

    let stale_count: i64 = match state.db.with_conn(|conn| {
        conn.query_row(
            "SELECT COUNT(*) FROM vault_document
             WHERE is_folder = 0 AND relative_path != '' AND updated_at <= ?1",
            rusqlite::params![cutoff],
            |r| r.get(0),
        )
        .map_err(Into::into)
    }) {
        Ok(c) => c,
        Err(e) => {
            tracing::warn!(error = %e, "stale monitor scan failed");
            return;
        }
    };

    if stale_count == 0 {
        return;
    }

    tracing::info!(count = stale_count, threshold_days, "stale vault documents detected");

    if let Ok(rev) = state.db.bump_revision("vault") {
        let _ = app.emit(
            "background:stale-documents",
            serde_json::json!({
                "count": stale_count,
                "thresholdDays": threshold_days,
                "revision": rev,
            }),
        );
        let _ = app.emit(
            "db:change",
            DbChangeEvent {
                domain: "vault".to_string(),
                revision: rev,
            },
        );
    }

    let body = format!(
        "{stale_count} vault document{} haven't been updated in {threshold_days}+ days.",
        if stale_count == 1 { "" } else { "s" }
    );
    let _ = app
        .notification()
        .builder()
        .title("Stale documents")
        .body(&body)
        .show();
}

pub fn spawn(app: AppHandle) {
    tauri::async_runtime::spawn(async move {
        tokio::time::sleep(SCAN_INTERVAL).await;

        loop {
            if let Some(state) = app.try_state::<AppState>() {
                scan_vault_stale(&app, state.inner());
            }
            tokio::time::sleep(SCAN_INTERVAL).await;
        }
    });
}
