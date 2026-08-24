use crate::commands::CmdResult;
use crate::security::SecurityStatus;
use crate::AppState;
use tauri::State;

#[tauri::command]
pub fn security_is_locked(state: State<'_, AppState>) -> bool {
    state.security.is_locked()
}

#[tauri::command]
pub fn security_lock(state: State<'_, AppState>) -> SecurityStatus {
    state.security.lock();
    state.security.status()
}

#[tauri::command]
pub fn security_unlock(state: State<'_, AppState>, reason: String) -> CmdResult<SecurityStatus> {
    state.security.unlock(&reason)?;
    Ok(state.security.status())
}

#[tauri::command]
pub fn security_biometric_available(state: State<'_, AppState>) -> bool {
    state.security.biometric_available()
}
