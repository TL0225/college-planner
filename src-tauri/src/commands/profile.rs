use crate::commands::CmdResult;
use crate::AppState;
use serde::Serialize;
use tauri::State;

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ProfileIdentityDto {
    pub id: Option<String>,
    pub full_name: String,
    pub email: String,
    pub university_name: String,
    pub major: String,
    pub graduation_year: Option<i64>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ExperienceDto {
    pub id: String,
    pub title: String,
    pub organization: String,
    pub start_date: Option<String>,
    pub end_date: Option<String>,
    pub summary: String,
}

#[tauri::command]
pub fn profile_get_identity(state: State<'_, AppState>) -> CmdResult<ProfileIdentityDto> {
    state
        .db
        .with_conn(|conn| {
            let mut stmt = conn.prepare(
                "SELECT id, full_name, email, university_name, major, graduation_year
                 FROM profile ORDER BY updated_at DESC LIMIT 1",
            )?;
            let mut rows = stmt.query_map([], |r| {
                Ok(ProfileIdentityDto {
                    id: Some(r.get(0)?),
                    full_name: r.get(1)?,
                    email: r.get(2)?,
                    university_name: r.get(3)?,
                    major: r.get(4)?,
                    graduation_year: r.get(5)?,
                })
            })?;
            if let Some(row) = rows.next() {
                Ok(row?)
            } else {
                Ok(ProfileIdentityDto {
                    id: None,
                    full_name: String::new(),
                    email: String::new(),
                    university_name: String::new(),
                    major: String::new(),
                    graduation_year: None,
                })
            }
        })
        .map_err(Into::into)
}

#[tauri::command]
pub fn profile_list_experiences(state: State<'_, AppState>) -> CmdResult<Vec<ExperienceDto>> {
    state
        .db
        .with_conn(|conn| {
            let mut stmt = conn.prepare(
                "SELECT id, title, organization, start_date, end_date, summary
                 FROM experience ORDER BY sort_order ASC, start_date DESC",
            )?;
            let rows = stmt
                .query_map([], |r| {
                    Ok(ExperienceDto {
                        id: r.get(0)?,
                        title: r.get(1)?,
                        organization: r.get(2)?,
                        start_date: r.get(3)?,
                        end_date: r.get(4)?,
                        summary: r.get(5)?,
                    })
                })?
                .collect::<Result<Vec<_>, _>>()?;
            Ok(rows)
        })
        .map_err(Into::into)
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AchievementDto {
    pub id: String,
    pub title: String,
    pub issuer: String,
    pub notes: String,
}

#[tauri::command]
pub fn profile_list_achievements(state: State<'_, AppState>) -> CmdResult<Vec<AchievementDto>> {
    state
        .db
        .with_conn(|conn| {
            let mut stmt = conn.prepare(
                "SELECT id, title, issuer, notes FROM achievement ORDER BY title ASC LIMIT 200",
            )?;
            let rows = stmt
                .query_map([], |r| {
                    Ok(AchievementDto {
                        id: r.get(0)?,
                        title: r.get(1)?,
                        issuer: r.get(2)?,
                        notes: r.get(3)?,
                    })
                })?
                .collect::<Result<Vec<_>, _>>()?;
            Ok(rows)
        })
        .map_err(Into::into)
}
