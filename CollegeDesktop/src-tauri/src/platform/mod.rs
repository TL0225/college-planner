//! OS-specific adapters: secrets, biometrics, window chrome, on-device AI devices.

pub mod window_chrome;

#[cfg(target_os = "windows")]
pub mod windows;

#[cfg(target_os = "macos")]
pub mod macos;

/// Backend label for Settings / AI status.
pub fn ai_device_backend() -> &'static str {
    #[cfg(target_os = "windows")]
    {
        windows::ai::device_label()
    }
    #[cfg(target_os = "macos")]
    {
        macos::ai::device_label()
    }
    #[cfg(not(any(target_os = "windows", target_os = "macos")))]
    {
        "cpu"
    }
}

/// Apply native window chrome after the main window is created (border, focus).
pub fn apply_main_window_chrome(window: &tauri::WebviewWindow) {
    if let Err(e) = window_chrome::apply(window) {
        tracing::warn!(error = %e, "window chrome apply skipped");
    }
}
