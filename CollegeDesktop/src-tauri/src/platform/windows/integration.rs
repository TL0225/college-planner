//! Central Windows 11 integration bootstrap.

use super::hwnd::hwnd_of;
use anyhow::Result;

pub fn initialize(window: &tauri::WebviewWindow) -> Result<()> {
    super::window_chrome::apply_no_accent_border(window)?;

    if let Ok(hwnd) = hwnd_of(window) {
        super::biometrics::set_main_hwnd(hwnd);
        let _ = super::shell::initialize_shell_integration(hwnd);
        let _ = super::taskbar::register_tab(window);
    }

    tracing::info!("Windows 11 platform integration initialized");
    Ok(())
}

pub fn on_window_focus_changed(window: &tauri::WebviewWindow, focused: bool) -> Result<()> {
    if focused {
        super::power::enable_efficiency_mode(false)?;
    } else {
        super::power::enable_efficiency_mode(true)?;
    }
    let _ = window;
    Ok(())
}
