//! Windows accent color, text scale, and high-contrast personalization.

use anyhow::{Context, Result};
use serde::Serialize;
use windows::core::PCWSTR;
use windows::Win32::System::Registry::{
    RegCloseKey, RegOpenKeyExW, RegQueryValueExW, HKEY, HKEY_CURRENT_USER, KEY_READ, REG_DWORD,
    REG_VALUE_TYPE,
};

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct WindowsPersonalization {
    pub accent_color: Option<String>,
    pub text_scale_percent: u32,
    pub high_contrast: bool,
}

fn wide(s: &str) -> Vec<u16> {
    use std::os::windows::prelude::OsStrExt;
    std::ffi::OsStr::new(s)
        .encode_wide()
        .chain(std::iter::once(0))
        .collect()
}

fn reg_open(path: &str) -> Result<HKEY> {
    let path_w = wide(path);
    let mut key = HKEY::default();
    unsafe {
        RegOpenKeyExW(
            HKEY_CURRENT_USER,
            PCWSTR(path_w.as_ptr()),
            0,
            KEY_READ,
            &mut key,
        )
        .ok()
        .context("RegOpenKeyExW failed")?;
    }
    Ok(key)
}

fn reg_read_dword(key: HKEY, name: &str) -> Result<u32> {
    let name_w = wide(name);
    let mut ty = REG_VALUE_TYPE::default();
    let mut data: u32 = 0;
    let mut size = std::mem::size_of::<u32>() as u32;
    unsafe {
        RegQueryValueExW(
            key,
            PCWSTR(name_w.as_ptr()),
            None,
            Some(&mut ty as *mut REG_VALUE_TYPE),
            Some(&mut data as *mut u32 as *mut u8),
            Some(&mut size),
        )
        .ok()
        .context("RegQueryValueExW failed")?;
    }
    Ok(data)
}

fn read_accent_color() -> Option<String> {
    let key = reg_open(r"Software\Microsoft\Windows\CurrentVersion\Explorer\Accent").ok()?;
    let color = reg_read_dword(key, "AccentColor").ok()?;
    unsafe {
        let _ = RegCloseKey(key);
    }
    let r = (color & 0xFF) as u8;
    let g = ((color >> 8) & 0xFF) as u8;
    let b = ((color >> 16) & 0xFF) as u8;
    Some(format!("#{:02x}{:02x}{:02x}", r, g, b))
}

fn read_text_scale_percent() -> u32 {
    if let Ok(key) = reg_open(r"Software\Microsoft\Accessibility") {
        if let Ok(scale) = reg_read_dword(key, "TextScaleFactor") {
            unsafe {
                let _ = RegCloseKey(key);
            }
            return scale.clamp(100, 225);
        }
        unsafe {
            let _ = RegCloseKey(key);
        }
    }
    if let Ok(key) = reg_open(r"Control Panel\Desktop") {
        if let Ok(log_pixels) = reg_read_dword(key, "LogPixels") {
            unsafe {
                let _ = RegCloseKey(key);
            }
            return ((log_pixels as f64 / 96.0) * 100.0).round() as u32;
        }
        unsafe {
            let _ = RegCloseKey(key);
        }
    }
    100
}

fn read_high_contrast() -> bool {
    if let Ok(key) = reg_open(r"Control Panel\Accessibility\HighContrast") {
        let active = reg_read_dword(key, "Flags").unwrap_or(0) != 0;
        unsafe {
            let _ = RegCloseKey(key);
        }
        return active;
    }
    false
}

pub fn read_personalization() -> WindowsPersonalization {
    WindowsPersonalization {
        accent_color: read_accent_color(),
        text_scale_percent: read_text_scale_percent(),
        high_contrast: read_high_contrast(),
    }
}
