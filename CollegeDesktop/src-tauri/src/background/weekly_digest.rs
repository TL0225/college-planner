//! Weekly notification digest — open tasks, upcoming events (7d), stale vault count.

use crate::AppState;
use chrono::{Duration, Utc};
use tauri::{AppHandle, Manager};
use tauri_plugin_notification::NotificationExt;

const WEEKLY_INTERVAL: std::time::Duration = std::time::Duration::from_secs(7 * 24 * 3600);

#[derive(Debug, Clone, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct WeeklyDigestContent {
    pub title: String,
    pub body: String,
    pub open_tasks: i64,
    pub upcoming_events: i64,
    pub stale_vault_count: i64,
}

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

pub fn build_digest(state: &AppState) -> WeeklyDigestContent {
    let now = Utc::now();
    let now_rfc = now.to_rfc3339();
    let week_end = (now + Duration::days(7)).to_rfc3339();

    let open_tasks: i64 = state
        .db
        .with_conn(|conn| {
            conn.query_row(
                "SELECT COUNT(*) FROM planner_task WHERE is_complete = 0",
                [],
                |r| r.get(0),
            )
            .map_err(Into::into)
        })
        .unwrap_or(0);

    let upcoming_events: i64 = state
        .db
        .with_conn(|conn| {
            conn.query_row(
                "SELECT COUNT(*) FROM calendar_event
                 WHERE start_at >= ?1 AND start_at <= ?2",
                rusqlite::params![now_rfc, week_end],
                |r| r.get(0),
            )
            .map_err(Into::into)
        })
        .unwrap_or(0);

    let threshold_days = stale_threshold_days(state);
    let cutoff = (now - Duration::days(threshold_days)).to_rfc3339();
    let stale_vault_count: i64 = state
        .db
        .with_conn(|conn| {
            conn.query_row(
                "SELECT COUNT(*) FROM vault_document
                 WHERE is_folder = 0 AND relative_path != '' AND updated_at <= ?1",
                rusqlite::params![cutoff],
                |r| r.get(0),
            )
            .map_err(Into::into)
        })
        .unwrap_or(0);

    let title = "Your Weekly College Digest".into();
    let body = format!(
        "{open_tasks} open task{} · {upcoming_events} upcoming event{} (7d) · {stale_vault_count} stale vault file{}",
        if open_tasks == 1 { "" } else { "s" },
        if upcoming_events == 1 { "" } else { "s" },
        if stale_vault_count == 1 { "" } else { "s" },
    );

    WeeklyDigestContent {
        title,
        body,
        open_tasks,
        upcoming_events,
        stale_vault_count,
    }
}

fn send_notification(app: &AppHandle, content: &WeeklyDigestContent) {
    let _ = app
        .notification()
        .builder()
        .title(&content.title)
        .body(&content.body)
        .show();
}

pub fn preview(app: &AppHandle, state: &AppState) -> WeeklyDigestContent {
    let content = build_digest(state);
    send_notification(app, &content);
    content
}

pub fn spawn(app: AppHandle) {
    tauri::async_runtime::spawn(async move {
        tokio::time::sleep(std::time::Duration::from_secs(3600)).await;

        loop {
            if let Some(state) = app.try_state::<AppState>() {
                let content = build_digest(state.inner());
                send_notification(&app, &content);
                tracing::info!(
                    open_tasks = content.open_tasks,
                    upcoming_events = content.upcoming_events,
                    stale = content.stale_vault_count,
                    "weekly digest notification sent"
                );
            }
            tokio::time::sleep(WEEKLY_INTERVAL).await;
        }
    });
}
