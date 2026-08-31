//! Shared HWND resolution for Win32 integrations.

use anyhow::{anyhow, Result};
use raw_window_handle::{HasWindowHandle, RawWindowHandle};
use windows::Win32::Foundation::HWND;

pub fn hwnd_of(window: &tauri::WebviewWindow) -> Result<HWND> {
    let handle = window
        .window_handle()
        .map_err(|e| anyhow!("window handle: {e}"))?;
    match handle.as_raw() {
        RawWindowHandle::Win32(h) => Ok(HWND(h.hwnd.get() as *mut _)),
        _ => Err(anyhow!("expected Win32 window handle")),
    }
}
