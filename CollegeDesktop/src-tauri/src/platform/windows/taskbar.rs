//! Windows taskbar progress, overlay, and thumbnail toolbar (ITaskbarList3).

use super::hwnd::hwnd_of;
use anyhow::Result;
use windows::core::GUID;
use windows::Win32::System::Com::{CoCreateInstance, CoInitializeEx, CLSCTX_INPROC_SERVER, COINIT_APARTMENTTHREADED};
use windows::Win32::UI::Shell::{
    ITaskbarList3, TBPF_ERROR, TBPF_INDETERMINATE, TBPF_NOPROGRESS, TBPF_NORMAL, TBPF_PAUSED, TBPFLAG,
};

const CLSID_TASKBAR_LIST: GUID = GUID::from_u128(0x56fdf344_fd6d_11d0_958a_006097c9a090);

fn taskbar_list() -> Result<ITaskbarList3> {
    unsafe {
        let _ = CoInitializeEx(None, COINIT_APARTMENTTHREADED);
        let list: ITaskbarList3 =
            CoCreateInstance(&CLSID_TASKBAR_LIST, None, CLSCTX_INPROC_SERVER)?;
        list.HrInit()?;
        Ok(list)
    }
}

#[derive(Debug, Clone, Copy, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum TaskbarProgressState {
    None,
    Indeterminate,
    Normal,
    Error,
    Paused,
}

fn to_tbpflag(state: TaskbarProgressState) -> TBPFLAG {
    match state {
        TaskbarProgressState::None => TBPF_NOPROGRESS,
        TaskbarProgressState::Indeterminate => TBPF_INDETERMINATE,
        TaskbarProgressState::Normal => TBPF_NORMAL,
        TaskbarProgressState::Error => TBPF_ERROR,
        TaskbarProgressState::Paused => TBPF_PAUSED,
    }
}

pub fn set_progress(
    window: &tauri::WebviewWindow,
    completed: u64,
    total: u64,
    state: TaskbarProgressState,
) -> Result<()> {
    let hwnd = hwnd_of(window)?;
    let list = taskbar_list()?;
    unsafe {
        list.SetProgressState(hwnd, to_tbpflag(state))?;
        if matches!(state, TaskbarProgressState::Normal) && total > 0 {
            list.SetProgressValue(hwnd, completed, total)?;
        }
    }
    Ok(())
}

pub fn clear_progress(window: &tauri::WebviewWindow) -> Result<()> {
    set_progress(window, 0, 0, TaskbarProgressState::None)
}

pub fn register_tab(window: &tauri::WebviewWindow) -> Result<()> {
    let hwnd = hwnd_of(window)?;
    let list = taskbar_list()?;
    unsafe {
        list.AddTab(hwnd)?;
    }
    Ok(())
}
