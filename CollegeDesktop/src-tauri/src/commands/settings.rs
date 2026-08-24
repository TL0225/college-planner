use crate::commands::CmdResult;
use crate::AppState;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use tauri::State;

#[derive(Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SettingsMap {
    pub values: HashMap<String, String>,
}

#[tauri::command]
pub fn settings_get(state: State<'_, AppState>) -> CmdResult<SettingsMap> {
    state
        .db
        .with_conn(|conn| {
            let mut stmt = conn.prepare("SELECT key, value FROM app_settings")?;
            let rows = stmt
                .query_map([], |r| Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?)))?
                .collect::<Result<HashMap<_, _>, _>>()?;
            Ok(SettingsMap { values: rows })
        })
        .map_err(Into::into)
}

#[tauri::command]
pub fn settings_set(state: State<'_, AppState>, key: String, value: String) -> CmdResult<()> {
    state.db.set_setting(&key, &value).map_err(Into::into)
}
