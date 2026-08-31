//! macOS Overlay titlebar is configured in tauri.conf; no extra border chrome.

use anyhow::Result;

pub fn apply_overlay_chrome(_window: &tauri::WebviewWindow) -> Result<()> {
    tracing::debug!("macOS overlay chrome active (tauri.conf titleBarStyle=Overlay)");
    Ok(())
}
