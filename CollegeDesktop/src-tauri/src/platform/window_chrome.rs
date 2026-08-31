//! Shared window chrome helpers (OS-specific impls below).

use anyhow::Result;

#[cfg(target_os = "windows")]
pub fn apply(window: &tauri::WebviewWindow) -> Result<()> {
    crate::platform::windows::window_chrome::apply_no_accent_border(window)
}

#[cfg(target_os = "macos")]
pub fn apply(window: &tauri::WebviewWindow) -> Result<()> {
    crate::platform::macos::window_chrome::apply_overlay_chrome(window)
}

#[cfg(not(any(target_os = "windows", target_os = "macos")))]
pub fn apply(_window: &tauri::WebviewWindow) -> Result<()> {
    Ok(())
}
