use crate::background::{watchdog, weekly_digest};
use crate::commands::CmdResult;
use crate::AppState;
use tauri::{AppHandle, State};

#[derive(Debug, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct WatchdogStatusDto {
    pub is_watching: bool,
    pub watched_count: usize,
    pub last_detected_path: Option<String>,
    pub last_detected_at: Option<String>,
}

#[tauri::command]
pub fn documents_watchdog_status() -> CmdResult<WatchdogStatusDto> {
    let status = watchdog::status_snapshot();
    Ok(WatchdogStatusDto {
        is_watching: status.is_watching,
        watched_count: status.watched_count,
        last_detected_path: status.last_detected_path,
        last_detected_at: status.last_detected_at,
    })
}

#[tauri::command]
pub fn background_weekly_digest_preview(
    app: AppHandle,
    state: State<'_, AppState>,
) -> CmdResult<weekly_digest::WeeklyDigestContent> {
    Ok(weekly_digest::preview(&app, state.inner()))
}
