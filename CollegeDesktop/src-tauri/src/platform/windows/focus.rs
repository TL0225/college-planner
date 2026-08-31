//! Windows focus session — prevents system sleep during study mode.

use serde::Serialize;
use windows::core::PCWSTR;
use windows::Win32::System::Power::{SetThreadExecutionState, ES_CONTINUOUS, ES_SYSTEM_REQUIRED};
use windows::Win32::System::Registry::{
    RegCloseKey, RegOpenKeyExW, RegQueryValueExW, HKEY, HKEY_CURRENT_USER, KEY_READ,
    REG_VALUE_TYPE,
};

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct FocusSessionStatus {
    pub supported: bool,
    pub active: bool,
    pub message: String,
}

static mut FOCUS_ACTIVE: bool = false;

fn wide(s: &str) -> Vec<u16> {
    use std::os::windows::prelude::OsStrExt;
    std::ffi::OsStr::new(s)
        .encode_wide()
        .chain(std::iter::once(0))
        .collect()
}

/// Best-effort Focus Assist / quiet-hours probe via registry.
fn focus_assist_active() -> Option<bool> {
    let path_w = wide(r"Software\Microsoft\Windows\CurrentVersion\FocusAssist");
    let mut key = HKEY::default();
    let opened = unsafe {
        RegOpenKeyExW(
            HKEY_CURRENT_USER,
            PCWSTR(path_w.as_ptr()),
            0,
            KEY_READ,
            &mut key,
        )
    };
    if opened.is_err() {
        return None;
    }

    let name_w = wide("ActiveScene");
    let mut ty = REG_VALUE_TYPE::default();
    let mut data: u32 = 0;
    let mut size = std::mem::size_of::<u32>() as u32;
    let read = unsafe {
        RegQueryValueExW(
            key,
            PCWSTR(name_w.as_ptr()),
            None,
            Some(&mut ty as *mut REG_VALUE_TYPE),
            Some(&mut data as *mut u32 as *mut u8),
            Some(&mut size),
        )
    };
    unsafe {
        let _ = RegCloseKey(key);
    }
    if read.is_err() {
        return None;
    }
    // 0 = off, 1 = priority only, 2 = alarms only (treated as active quiet focus).
    Some(data > 0)
}

fn prevent_sleep(on: bool) {
    unsafe {
        if on {
            let _ = SetThreadExecutionState(ES_CONTINUOUS | ES_SYSTEM_REQUIRED);
        } else {
            let _ = SetThreadExecutionState(ES_CONTINUOUS);
        }
    }
}

/// Start a focus session: keep the system awake for study mode.
pub fn start_focus_session(duration_minutes: u32) -> FocusSessionStatus {
    prevent_sleep(true);
    unsafe {
        FOCUS_ACTIVE = true;
    }

    let quiet_note = match focus_assist_active() {
        Some(true) => " Windows Focus Assist is already active on this PC.",
        Some(false) => " System sleep is prevented for this session.",
        None => " System sleep is prevented for this session.",
    };

    tracing::info!(duration_minutes, "Focus session started (sleep prevented)");
    FocusSessionStatus {
        supported: true,
        active: true,
        message: format!(
            "Study focus active for {duration_minutes} minutes.{quiet_note} In-app notifications are muted."
        ),
    }
}

pub fn end_focus_session() -> FocusSessionStatus {
    prevent_sleep(false);
    unsafe {
        FOCUS_ACTIVE = false;
    }
    tracing::info!("Focus session ended (sleep prevention cleared)");
    FocusSessionStatus {
        supported: true,
        active: false,
        message: "Focus session ended. System sleep settings restored.".into(),
    }
}

pub fn status() -> FocusSessionStatus {
    let active = unsafe { FOCUS_ACTIVE };
    FocusSessionStatus {
        supported: true,
        active,
        message: if active {
            "Study focus session is active — system sleep is prevented.".into()
        } else {
            "No active focus session.".into()
        },
    }
}
