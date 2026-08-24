//! Background services — parity with Swift `BackgroundServiceManifest` tier-1 schedulers.

pub mod scheduler;
pub mod screenshot_triage;
pub mod stale_monitor;
pub mod watchdog;
pub mod weekly_digest;

use tauri::AppHandle;

/// Start all background tasks after `AppState` is managed.
pub async fn start_all(app: AppHandle) {
    scheduler::spawn(app.clone());
    stale_monitor::spawn(app.clone());
    screenshot_triage::spawn(app.clone());
    weekly_digest::spawn(app.clone());
    watchdog::spawn(app);
}
