use crate::commands::CmdResult;
use crate::db::DbChangeEvent;
use crate::AppState;
use chrono::Utc;
use serde::{Deserialize, Serialize};
use tauri::{AppHandle, Emitter, State};
use uuid::Uuid;

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct FocusBlockDto {
    pub id: String,
    pub title: String,
    pub duration_minutes: i64,
    pub sort_order: i64,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UpsertFocusBlockInput {
    pub id: Option<String>,
    pub title: String,
    pub duration_minutes: Option<i64>,
    pub sort_order: Option<i64>,
}

#[tauri::command]
pub fn calendar_list_focus_blocks(state: State<'_, AppState>) -> CmdResult<Vec<FocusBlockDto>> {
    state
        .db
        .with_conn(|conn| {
            let mut stmt = conn.prepare(
                "SELECT id, title, duration_minutes, sort_order
                 FROM focus_block
                 ORDER BY sort_order ASC, title ASC",
            )?;
            let rows = stmt
                .query_map([], |r| {
                    Ok(FocusBlockDto {
                        id: r.get(0)?,
                        title: r.get(1)?,
                        duration_minutes: r.get(2)?,
                        sort_order: r.get(3)?,
                    })
                })?
                .collect::<Result<Vec<_>, _>>()?;
            Ok(rows)
        })
        .map_err(Into::into)
}

#[tauri::command]
pub fn calendar_upsert_focus_block(
    app: AppHandle,
    state: State<'_, AppState>,
    input: UpsertFocusBlockInput,
) -> CmdResult<String> {
    let id = input
        .id
        .filter(|s| !s.trim().is_empty())
        .unwrap_or_else(|| Uuid::new_v4().to_string());
    let duration = input.duration_minutes.unwrap_or(45).clamp(5, 480);
    let sort = input.sort_order.unwrap_or(0);
    let now = Utc::now().to_rfc3339();
    state.db.with_conn(|conn| {
        conn.execute(
            "INSERT INTO focus_block (id, title, duration_minutes, sort_order, created_at, updated_at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?5)
             ON CONFLICT(id) DO UPDATE SET
               title = excluded.title,
               duration_minutes = excluded.duration_minutes,
               sort_order = excluded.sort_order,
               updated_at = excluded.updated_at",
            rusqlite::params![id, input.title.trim(), duration, sort, now],
        )?;
        Ok(())
    })?;
    let rev = state.db.bump_revision("calendar")?;
    let _ = app.emit(
        "db:change",
        DbChangeEvent {
            domain: "calendar".into(),
            revision: rev,
        },
    );
    Ok(id)
}

#[tauri::command]
pub fn calendar_delete_focus_block(
    app: AppHandle,
    state: State<'_, AppState>,
    id: String,
) -> CmdResult<()> {
    state.db.with_conn(|conn| {
        conn.execute("DELETE FROM focus_block WHERE id = ?1", rusqlite::params![id])?;
        Ok(())
    })?;
    let rev = state.db.bump_revision("calendar")?;
    let _ = app.emit(
        "db:change",
        DbChangeEvent {
            domain: "calendar".into(),
            revision: rev,
        },
    );
    Ok(())
}
