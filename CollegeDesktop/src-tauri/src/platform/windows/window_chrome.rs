//! Windows 11 DWM materials, immersive dark mode, corners, and DPI awareness.

use super::hwnd::hwnd_of;
use anyhow::{anyhow, Result};
use windows::Win32::Foundation::{BOOL, HWND};
use windows::Win32::Graphics::Dwm::{
    DwmSetWindowAttribute, DWMWA_BORDER_COLOR, DWMWA_COLOR_NONE,
    DWMWA_SYSTEMBACKDROP_TYPE, DWMWA_USE_IMMERSIVE_DARK_MODE, DWMWA_WINDOW_CORNER_PREFERENCE,
    DWMSBT_MAINWINDOW, DWMSBT_TABBEDWINDOW, DWMWCP_ROUND,
};
use windows::Win32::UI::HiDpi::{
    SetProcessDpiAwarenessContext, DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2,
};
use windows::Win32::UI::WindowsAndMessaging::{
    GetWindowLongW, SetWindowLongW, SetWindowPos, GWL_STYLE, SWP_FRAMECHANGED, SWP_NOMOVE,
    SWP_NOOWNERZORDER, SWP_NOSIZE, SWP_NOZORDER, WS_CAPTION, WS_MAXIMIZEBOX, WS_MINIMIZEBOX,
    WS_SYSMENU, WS_THICKFRAME,
};

fn strip_os_titlebar(hwnd: HWND) -> Result<()> {
    unsafe {
        let style = GetWindowLongW(hwnd, GWL_STYLE) as u32;
        let strip = (WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX | WS_MAXIMIZEBOX).0;
        let next = (style & !strip) | WS_THICKFRAME.0;
        SetWindowLongW(hwnd, GWL_STYLE, next as i32);
        SetWindowPos(
            hwnd,
            None,
            0,
            0,
            0,
            0,
            SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOOWNERZORDER | SWP_FRAMECHANGED,
        )
        .map_err(|e| anyhow!("SetWindowPos(SWP_FRAMECHANGED): {e}"))?;
    }
    Ok(())
}

fn dwm_set_bool(hwnd: HWND, attr: windows::Win32::Graphics::Dwm::DWMWINDOWATTRIBUTE, on: bool) -> Result<()> {
    let value = BOOL::from(on);
    unsafe {
        DwmSetWindowAttribute(
            hwnd,
            attr,
            &value as *const _ as *const _,
            std::mem::size_of::<BOOL>() as u32,
        )
        .map_err(|e| anyhow!("DwmSetWindowAttribute({attr:?}): {e}"))?;
    }
    Ok(())
}

/// Enable per-monitor V2 DPI awareness for crisp mixed-DPI rendering.
pub fn ensure_per_monitor_dpi() {
    unsafe {
        let _ = SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
    }
}

/// Apply Mica (main window) or Mica Alt (tabbed super-app) backdrop.
pub fn set_mica_backdrop(hwnd: HWND, mica_alt: bool) -> Result<()> {
    let backdrop = if mica_alt {
        DWMSBT_TABBEDWINDOW
    } else {
        DWMSBT_MAINWINDOW
    };
    unsafe {
        DwmSetWindowAttribute(
            hwnd,
            DWMWA_SYSTEMBACKDROP_TYPE,
            &backdrop as *const _ as *const _,
            std::mem::size_of::<i32>() as u32,
        )
        .map_err(|e| anyhow!("DwmSetWindowAttribute(DWMWA_SYSTEMBACKDROP_TYPE): {e}"))?;
    }
    Ok(())
}

/// Sync native window frame with app dark/light theme.
pub fn set_immersive_dark_mode(hwnd: HWND, dark: bool) -> Result<()> {
    dwm_set_bool(hwnd, DWMWA_USE_IMMERSIVE_DARK_MODE, dark)
}

fn apply_rounded_corners(hwnd: HWND) -> Result<()> {
    let pref = DWMWCP_ROUND;
    unsafe {
        DwmSetWindowAttribute(
            hwnd,
            DWMWA_WINDOW_CORNER_PREFERENCE,
            &pref as *const _ as *const _,
            std::mem::size_of::<i32>() as u32,
        )
        .map_err(|e| anyhow!("DwmSetWindowAttribute(DWMWA_WINDOW_CORNER_PREFERENCE): {e}"))?;
    }
    Ok(())
}

pub fn apply_no_accent_border(window: &tauri::WebviewWindow) -> Result<()> {
    ensure_per_monitor_dpi();

    match window.set_decorations(false) {
        Ok(()) => tracing::info!("Tauri set_decorations(false) ok"),
        Err(e) => tracing::warn!("Tauri set_decorations(false) failed: {e}"),
    }

    let hwnd = hwnd_of(window)?;
    strip_os_titlebar(hwnd)?;

    unsafe {
        let color = DWMWA_COLOR_NONE;
        DwmSetWindowAttribute(
            hwnd,
            DWMWA_BORDER_COLOR,
            &color as *const _ as *const _,
            std::mem::size_of_val(&color) as u32,
        )
        .map_err(|e| anyhow!("DwmSetWindowAttribute(DWMWA_BORDER_COLOR): {e}"))?;
    }

    let _ = apply_rounded_corners(hwnd);
    let _ = set_mica_backdrop(hwnd, true);
    let _ = set_immersive_dark_mode(hwnd, false);

    tracing::info!("Windows 11 DWM chrome applied (Mica Alt, rounded corners, DPI V2)");
    Ok(())
}

pub fn sync_theme(window: &tauri::WebviewWindow, dark: bool) -> Result<()> {
    let hwnd = hwnd_of(window)?;
    set_immersive_dark_mode(hwnd, dark)
}
