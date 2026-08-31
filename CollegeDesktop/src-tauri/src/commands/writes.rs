//! Shared write commands + demo seed for interactive module flows.

use crate::commands::academics::{fulfillment_setting_key, normalize_code as normalize_course_code};
use crate::commands::CmdResult;
use crate::commands::calendar::DEFAULT_CALENDAR_SOURCE_ID;
use crate::db::DbChangeEvent;
use crate::AppState;
use chrono::{Duration, Utc};
use serde::Deserialize;
use tauri::{AppHandle, Emitter, State};
use uuid::Uuid;

fn emit_change(app: &AppHandle, domain: &str, revision: i64) {
    let _ = app.emit(
        "db:change",
        DbChangeEvent {
            domain: domain.to_string(),
            revision,
        },
    );
}

fn bump(app: &AppHandle, state: &AppState, domain: &str) -> CmdResult<i64> {
    let rev = state.db.bump_revision(domain)?;
    emit_change(app, domain, rev);
    Ok(rev)
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UpsertSemesterInput {
    pub id: Option<String>,
    pub year: i64,
    pub season: String,
    pub label: Option<String>,
    pub is_current: Option<bool>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UpsertCourseInput {
    pub id: Option<String>,
    pub semester_id: String,
    pub code: String,
    pub title: String,
    pub credits: Option<f64>,
    pub status: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UpsertEventInput {
    pub id: Option<String>,
    pub title: String,
    pub start_at: String,
    pub end_at: Option<String>,
    pub location: Option<String>,
    pub all_day: Option<bool>,
    pub color: Option<String>,
    pub recurrence: Option<String>,
    pub course_id: Option<String>,
    pub semester_id: Option<String>,
    pub notes: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AddRequirementCourseInput {
    pub semester_id: String,
    pub code: String,
    pub title: Option<String>,
    pub credits: Option<f64>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AssignFulfillmentInput {
    pub category_id: String,
    pub course_code: String,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UpsertTaskInput {
    pub id: Option<String>,
    pub title: String,
    pub due_at: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UpsertApplicationInput {
    pub id: Option<String>,
    pub company: String,
    pub role_title: String,
    pub status: Option<String>,
    pub location: Option<String>,
    pub url: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UpsertAccountInput {
    pub id: Option<String>,
    pub name: String,
    pub institution: Option<String>,
    pub account_type: Option<String>,
    pub balance: Option<f64>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UpsertTransactionInput {
    pub id: Option<String>,
    pub account_id: String,
    pub amount: f64,
    pub payee: String,
    pub category: Option<String>,
    pub memo: Option<String>,
    pub posted_at: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UpsertVaultDocInput {
    pub title: String,
    pub category: Option<String>,
    pub mime_type: Option<String>,
    pub parent_folder_id: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UpsertProfileInput {
    pub full_name: String,
    pub email: Option<String>,
    pub university_name: Option<String>,
    pub major: Option<String>,
    pub graduation_year: Option<i64>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UpsertExperienceInput {
    pub id: Option<String>,
    pub title: String,
    pub organization: String,
    pub summary: Option<String>,
    pub start_date: Option<String>,
    pub end_date: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UpsertAchievementInput {
    pub id: Option<String>,
    pub title: String,
    pub issuer: Option<String>,
    pub notes: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UpsertBudgetInput {
    pub id: Option<String>,
    pub name: String,
    pub category: Option<String>,
    pub amount: f64,
    pub period: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UpsertRecurringInput {
    pub id: Option<String>,
    pub account_id: Option<String>,
    pub title: String,
    pub amount: f64,
    pub cadence: Option<String>,
    pub next_due: Option<String>,
    pub category: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UpsertGoalInput {
    pub id: Option<String>,
    pub name: String,
    pub target_amount: f64,
    pub current_amount: Option<f64>,
    pub deadline: Option<String>,
    pub notes: Option<String>,
    pub sort_order: Option<i64>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UpsertInventoryItemInput {
    pub id: Option<String>,
    pub name: String,
    pub category: Option<String>,
    pub purchase_date: Option<String>,
    pub value: Option<f64>,
    pub notes: Option<String>,
    pub sort_order: Option<i64>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UpsertReceiptInput {
    pub id: Option<String>,
    pub title: String,
    pub merchant: Option<String>,
    pub amount: Option<f64>,
    pub purchased_at: Option<String>,
    pub category: Option<String>,
    pub notes: Option<String>,
    pub vault_doc_id: Option<String>,
    pub sort_order: Option<i64>,
}

#[tauri::command]
pub fn academics_upsert_semester(
    app: AppHandle,
    state: State<'_, AppState>,
    input: UpsertSemesterInput,
) -> CmdResult<String> {
    let label = input
        .label
        .unwrap_or_else(|| format!("{} {}", input.season, input.year));
    let is_current = i64::from(input.is_current.unwrap_or(false));
    let id = if let Some(existing) = input.id.filter(|s| !s.is_empty()) {
        state.db.with_conn(|conn| {
            if is_current == 1 {
                conn.execute("UPDATE planner_semester SET is_current = 0", [])?;
            }
            conn.execute(
                "UPDATE planner_semester
                 SET year = ?1, season = ?2, label = ?3, is_current = ?4
                 WHERE id = ?5",
                rusqlite::params![input.year, input.season, label, is_current, existing],
            )?;
            Ok(())
        })?;
        existing
    } else {
        let id = Uuid::new_v4().to_string();
        state.db.with_conn(|conn| {
            if is_current == 1 {
                conn.execute("UPDATE planner_semester SET is_current = 0", [])?;
            }
            conn.execute(
                "INSERT INTO planner_semester (id, plan_id, year, season, label, is_current, sort_order)
                 VALUES (?1, NULL, ?2, ?3, ?4, ?5, 0)",
                rusqlite::params![id, input.year, input.season, label, is_current],
            )?;
            Ok(())
        })?;
        id
    };
    bump(&app, &state, "planner")?;
    Ok(id)
}

#[tauri::command]
pub fn academics_upsert_course(
    app: AppHandle,
    state: State<'_, AppState>,
    input: UpsertCourseInput,
) -> CmdResult<String> {
    let status = input.status.unwrap_or_else(|| "planned".into());
    let credits = input.credits.unwrap_or(3.0);
    let id = if let Some(existing) = input.id.filter(|s| !s.is_empty()) {
        state.db.with_conn(|conn| {
            conn.execute(
                "UPDATE planner_course
                 SET semester_id = ?1, code = ?2, title = ?3, credits = ?4, status = ?5
                 WHERE id = ?6",
                rusqlite::params![
                    input.semester_id,
                    input.code,
                    input.title,
                    credits,
                    status,
                    existing
                ],
            )?;
            Ok(())
        })?;
        existing
    } else {
        let id = Uuid::new_v4().to_string();
        state.db.with_conn(|conn| {
            conn.execute(
                "INSERT INTO planner_course
                 (id, semester_id, catalog_course_id, code, title, credits, grade, status, sort_order)
                 VALUES (?1, ?2, NULL, ?3, ?4, ?5, NULL, ?6, 0)",
                rusqlite::params![id, input.semester_id, input.code, input.title, credits, status],
            )?;
            Ok(())
        })?;
        id
    };
    bump(&app, &state, "planner")?;
    Ok(id)
}

#[tauri::command]
pub fn academics_update_course_status(
    app: AppHandle,
    state: State<'_, AppState>,
    id: String,
    status: String,
) -> CmdResult<()> {
    state.db.with_conn(|conn| {
        conn.execute(
            "UPDATE planner_course SET status = ?1 WHERE id = ?2",
            rusqlite::params![status, id],
        )?;
        Ok(())
    })?;
    bump(&app, &state, "planner")?;
    Ok(())
}

#[tauri::command]
pub fn academics_update_course_grade(
    app: AppHandle,
    state: State<'_, AppState>,
    id: String,
    grade: Option<String>,
) -> CmdResult<()> {
    state.db.with_conn(|conn| {
        conn.execute(
            "UPDATE planner_course SET grade = ?1 WHERE id = ?2",
            rusqlite::params![grade.filter(|g| !g.trim().is_empty()), id],
        )?;
        Ok(())
    })?;
    bump(&app, &state, "planner")?;
    Ok(())
}

#[tauri::command]
pub fn academics_list_courses(
    state: State<'_, AppState>,
    semester_id: Option<String>,
) -> CmdResult<Vec<serde_json::Value>> {
    state
        .db
        .with_conn(|conn| {
            let map_row = |r: &rusqlite::Row<'_>| {
                Ok(serde_json::json!({
                    "id": r.get::<_, String>(0)?,
                    "semesterId": r.get::<_, String>(1)?,
                    "code": r.get::<_, String>(2)?,
                    "title": r.get::<_, String>(3)?,
                    "credits": r.get::<_, f64>(4)?,
                    "status": r.get::<_, String>(5)?,
                    "grade": r.get::<_, Option<String>>(6)?,
                }))
            };
            let mut out = Vec::new();
            if let Some(sid) = semester_id {
                let mut stmt = conn.prepare(
                    "SELECT id, semester_id, code, title, credits, status, grade
                     FROM planner_course WHERE semester_id = ?1
                     ORDER BY sort_order ASC, code ASC",
                )?;
                for row in stmt.query_map([sid], map_row)? {
                    out.push(row?);
                }
            } else {
                let mut stmt = conn.prepare(
                    "SELECT id, semester_id, code, title, credits, status, grade
                     FROM planner_course ORDER BY sort_order ASC, code ASC LIMIT 200",
                )?;
                for row in stmt.query_map([], map_row)? {
                    out.push(row?);
                }
            }
            Ok(out)
        })
        .map_err(Into::into)
}

#[tauri::command]
pub fn academics_add_requirement_course(
    app: AppHandle,
    state: State<'_, AppState>,
    input: AddRequirementCourseInput,
) -> CmdResult<bool> {
    let code = input.code.trim().to_uppercase();
    if code.is_empty() {
        return Ok(false);
    }
    let title = input.title.unwrap_or_default().trim().to_string();
    let credits = input.credits.unwrap_or(3.0);

    let changed = state.db.with_conn(|conn| {
            use rusqlite::OptionalExtension;

            let sem_exists: i64 = conn.query_row(
                "SELECT COUNT(*) FROM planner_semester WHERE id = ?1",
                [&input.semester_id],
                |r| r.get(0),
            )?;
            if sem_exists == 0 {
                return Ok(false);
            }

            let existing: Option<(String, String, String, f64)> = conn
                .query_row(
                    "SELECT id, semester_id, title, credits FROM planner_course WHERE UPPER(code) = ?1 LIMIT 1",
                    [&code],
                    |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?)),
                )
                .optional()?;

            if let Some((id, sem_id, existing_title, existing_credits)) = existing {
                if sem_id == input.semester_id {
                    return Ok(false);
                }
                conn.execute(
                    "UPDATE planner_course SET semester_id = ?1 WHERE id = ?2",
                    rusqlite::params![input.semester_id, id],
                )?;
                if !title.is_empty() && existing_title.trim().is_empty() {
                    conn.execute(
                        "UPDATE planner_course SET title = ?1 WHERE id = ?2",
                        rusqlite::params![title, id],
                    )?;
                }
                if credits > 0.0 && existing_credits == 0.0 {
                    conn.execute(
                        "UPDATE planner_course SET credits = ?1 WHERE id = ?2",
                        rusqlite::params![credits, id],
                    )?;
                }
                return Ok(true);
            }

            let id = Uuid::new_v4().to_string();
            let course_title = if title.is_empty() {
                code.clone()
            } else {
                title
            };
            conn.execute(
                "INSERT INTO planner_course
                 (id, semester_id, catalog_course_id, code, title, credits, grade, status, sort_order)
                 VALUES (?1, ?2, NULL, ?3, ?4, ?5, NULL, 'planned', 0)",
                rusqlite::params![id, input.semester_id, code, course_title, credits],
            )?;
            Ok(true)
        })?;

    if changed {
        bump(&app, &state, "planner")?;
    }
    Ok(changed)
}

#[tauri::command]
pub fn academics_assign_fulfillment(
    app: AppHandle,
    state: State<'_, AppState>,
    input: AssignFulfillmentInput,
) -> CmdResult<bool> {
    let category_id = input.category_id.trim();
    let code = normalize_course_code(&input.course_code);
    if category_id.is_empty() || code.is_empty() {
        return Ok(false);
    }

    let key = fulfillment_setting_key(category_id);
    let changed = state.db.with_conn(|conn| {
        use rusqlite::OptionalExtension;
        let existing: Option<String> = conn
            .query_row(
                "SELECT value FROM app_settings WHERE key = ?1",
                [&key],
                |r| r.get(0),
            )
            .optional()?;
        let mut codes: Vec<String> = existing
            .as_deref()
            .and_then(|v| serde_json::from_str(v).ok())
            .unwrap_or_default();
        if codes.iter().any(|c| normalize_course_code(c) == code) {
            return Ok(false);
        }
        codes.push(code);
        conn.execute(
            "INSERT INTO app_settings (key, value, updated_at)
             VALUES (?1, ?2, datetime('now'))
             ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = datetime('now')",
            rusqlite::params![key, serde_json::to_string(&codes)?],
        )?;
        Ok(true)
    })?;

    if changed {
        bump(&app, &state, "catalog")?;
    }
    Ok(changed)
}

#[tauri::command]
pub fn calendar_upsert_event(
    app: AppHandle,
    state: State<'_, AppState>,
    input: UpsertEventInput,
) -> CmdResult<String> {
    let now = Utc::now().to_rfc3339();
    let all_day = i64::from(input.all_day.unwrap_or(false));
    let location = input.location.unwrap_or_default();
    let color = input.color.unwrap_or_default();
    let notes = input.notes.unwrap_or_default();
    let course_id = input.course_id.filter(|s| !s.is_empty());
    let semester_id = input.semester_id.filter(|s| !s.is_empty());
    let recurrence = input
        .recurrence
        .filter(|r| matches!(r.as_str(), "none" | "weekly" | "monthly"))
        .unwrap_or_else(|| "none".to_string());
    let id = if let Some(existing) = input.id.filter(|s| !s.is_empty()) {
        state.db.with_conn(|conn| {
            conn.execute(
                "UPDATE calendar_event
                 SET title = ?1, start_at = ?2, end_at = ?3, all_day = ?4, location = ?5,
                     color = ?6, recurrence = ?7, notes = ?8, course_id = ?9, semester_id = ?10,
                     updated_at = ?11
                 WHERE id = ?12",
                rusqlite::params![
                    input.title,
                    input.start_at,
                    input.end_at,
                    all_day,
                    location,
                    color,
                    recurrence,
                    notes,
                    course_id,
                    semester_id,
                    now,
                    existing
                ],
            )?;
            Ok(())
        })?;
        existing
    } else {
        let id = Uuid::new_v4().to_string();
        state.db.with_conn(|conn| {
            conn.execute(
                "INSERT INTO calendar_event
                 (id, title, start_at, end_at, all_day, location, notes, provider, provider_event_id,
                  semester_id, course_id, color_hex, color, recurrence, source_id, created_at, updated_at)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, 'local', NULL, ?8, ?9, NULL, ?10, ?11, ?12, ?13, ?13)",
                rusqlite::params![
                    id,
                    input.title,
                    input.start_at,
                    input.end_at,
                    all_day,
                    location,
                    notes,
                    semester_id,
                    course_id,
                    color,
                    recurrence,
                    DEFAULT_CALENDAR_SOURCE_ID,
                    now
                ],
            )?;
            Ok(())
        })?;
        id
    };
    bump(&app, &state, "calendar")?;
    Ok(id)
}

#[tauri::command]
pub fn calendar_upsert_task(
    app: AppHandle,
    state: State<'_, AppState>,
    input: UpsertTaskInput,
) -> CmdResult<String> {
    let id = if let Some(existing) = input.id.filter(|s| !s.is_empty()) {
        state.db.with_conn(|conn| {
            conn.execute(
                "UPDATE planner_task SET title = ?1, due_at = ?2 WHERE id = ?3",
                rusqlite::params![input.title, input.due_at, existing],
            )?;
            Ok(())
        })?;
        existing
    } else {
        let id = Uuid::new_v4().to_string();
        state.db.with_conn(|conn| {
            conn.execute(
                "INSERT INTO planner_task
                 (id, semester_id, course_id, title, due_at, is_complete, notes, lms_item_id)
                 VALUES (?1, NULL, NULL, ?2, ?3, 0, '', NULL)",
                rusqlite::params![id, input.title, input.due_at],
            )?;
            Ok(())
        })?;
        id
    };
    bump(&app, &state, "planner")?;
    bump(&app, &state, "calendar")?;
    Ok(id)
}

#[tauri::command]
pub fn calendar_toggle_task_complete(
    app: AppHandle,
    state: State<'_, AppState>,
    id: String,
) -> CmdResult<()> {
    state.db.with_conn(|conn| {
        conn.execute(
            "UPDATE planner_task SET is_complete = CASE WHEN is_complete = 0 THEN 1 ELSE 0 END WHERE id = ?1",
            rusqlite::params![id],
        )?;
        Ok(())
    })?;
    bump(&app, &state, "planner")?;
    bump(&app, &state, "calendar")?;
    Ok(())
}

#[tauri::command]
pub fn career_upsert_application(
    app: AppHandle,
    state: State<'_, AppState>,
    input: UpsertApplicationInput,
) -> CmdResult<String> {
    let now = Utc::now().to_rfc3339();
    let status = input.status.unwrap_or_else(|| "interested".into());
    let location = input.location.unwrap_or_default();
    let url = input.url.unwrap_or_default();
    let id = if let Some(existing) = input.id.filter(|s| !s.is_empty()) {
        state.db.with_conn(|conn| {
            conn.execute(
                "UPDATE job_application
                 SET company = ?1, role_title = ?2, status = ?3, location = ?4, url = ?5, updated_at = ?6
                 WHERE id = ?7",
                rusqlite::params![
                    input.company,
                    input.role_title,
                    status,
                    location,
                    url,
                    now,
                    existing
                ],
            )?;
            Ok(())
        })?;
        existing
    } else {
        let id = Uuid::new_v4().to_string();
        state.db.with_conn(|conn| {
            conn.execute(
                "INSERT INTO job_application
                 (id, company, role_title, status, location, url, applied_at, notes, salary_text,
                  sort_order, created_at, updated_at)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, NULL, '', '', 0, ?7, ?7)",
                rusqlite::params![
                    id,
                    input.company,
                    input.role_title,
                    status,
                    location,
                    url,
                    now
                ],
            )?;
            Ok(())
        })?;
        id
    };
    bump(&app, &state, "career")?;
    Ok(id)
}

#[tauri::command]
pub fn career_update_application_status(
    app: AppHandle,
    state: State<'_, AppState>,
    id: String,
    status: String,
) -> CmdResult<()> {
    let now = Utc::now().to_rfc3339();
    state.db.with_conn(|conn| {
        conn.execute(
            "UPDATE job_application SET status = ?1, updated_at = ?2 WHERE id = ?3",
            rusqlite::params![status, now, id],
        )?;
        Ok(())
    })?;
    bump(&app, &state, "career")?;
    Ok(())
}

#[tauri::command]
pub fn career_move_application(
    app: AppHandle,
    state: State<'_, AppState>,
    id: String,
    status: String,
    sort_order: Option<i64>,
) -> CmdResult<()> {
    let now = Utc::now().to_rfc3339();
    state.db.with_conn(|conn| {
        let order = if let Some(order) = sort_order {
            order
        } else {
            conn.query_row(
                "SELECT COALESCE(MAX(sort_order), 0) + 1 FROM job_application WHERE status = ?1",
                rusqlite::params![status],
                |r| r.get(0),
            )
            .unwrap_or(1)
        };
        if status == "applied" {
            conn.execute(
                "UPDATE job_application
                 SET status = ?1, sort_order = ?2, updated_at = ?3,
                     applied_at = COALESCE(applied_at, ?3)
                 WHERE id = ?4",
                rusqlite::params![status, order, now, id],
            )?;
        } else {
            conn.execute(
                "UPDATE job_application
                 SET status = ?1, sort_order = ?2, updated_at = ?3
                 WHERE id = ?4",
                rusqlite::params![status, order, now, id],
            )?;
        }
        Ok(())
    })?;
    bump(&app, &state, "career")?;
    Ok(())
}

#[tauri::command]
pub fn career_reorder_applications(
    app: AppHandle,
    state: State<'_, AppState>,
    status: String,
    ordered_ids: Vec<String>,
) -> CmdResult<()> {
    let now = Utc::now().to_rfc3339();
    state.db.with_conn(|conn| {
        for (sort_order, id) in ordered_ids.iter().enumerate() {
            conn.execute(
                "UPDATE job_application
                 SET sort_order = ?1, updated_at = ?2
                 WHERE id = ?3 AND status = ?4",
                rusqlite::params![sort_order as i64, now, id, status],
            )?;
        }
        Ok(())
    })?;
    bump(&app, &state, "career")?;
    Ok(())
}

#[tauri::command]
pub fn career_apply_complete(
    app: AppHandle,
    state: State<'_, AppState>,
    id: String,
) -> CmdResult<()> {
    let now = Utc::now().to_rfc3339();
    state.db.with_conn(|conn| {
        let sort: i64 = conn
            .query_row(
                "SELECT COALESCE(MAX(sort_order), 0) + 1 FROM job_application WHERE status = 'applied'",
                [],
                |r| r.get(0),
            )
            .unwrap_or(1);
        conn.execute(
            "UPDATE job_application
             SET status = 'applied',
                 sort_order = ?1,
                 updated_at = ?2,
                 applied_at = COALESCE(applied_at, ?2),
                 notes = CASE
                   WHEN instr(notes, 'Applied via College apply window') > 0 THEN notes
                   WHEN trim(notes) = '' THEN 'Applied via College apply window.'
                   ELSE trim(notes || char(10) || 'Applied via College apply window.')
                 END
             WHERE id = ?3",
            rusqlite::params![sort, now, id],
        )?;
        Ok(())
    })?;
    bump(&app, &state, "career")?;
    Ok(())
}

#[tauri::command]
pub fn finance_upsert_account(
    app: AppHandle,
    state: State<'_, AppState>,
    input: UpsertAccountInput,
) -> CmdResult<String> {
    let institution = input.institution.unwrap_or_default();
    let account_type = input.account_type.unwrap_or_else(|| "checking".into());
    let balance = input.balance.unwrap_or(0.0);
    let id = if let Some(existing) = input.id.filter(|s| !s.is_empty()) {
        state.db.with_conn(|conn| {
            conn.execute(
                "UPDATE finance_account
                 SET name = ?1, institution = ?2, account_type = ?3, balance = ?4
                 WHERE id = ?5",
                rusqlite::params![input.name, institution, account_type, balance, existing],
            )?;
            Ok(())
        })?;
        existing
    } else {
        let id = Uuid::new_v4().to_string();
        state.db.with_conn(|conn| {
            conn.execute(
                "INSERT INTO finance_account
                 (id, name, institution, account_type, currency, balance, is_hidden, sort_order)
                 VALUES (?1, ?2, ?3, ?4, 'USD', ?5, 0, 0)",
                rusqlite::params![id, input.name, institution, account_type, balance],
            )?;
            Ok(())
        })?;
        id
    };
    bump(&app, &state, "finance")?;
    Ok(id)
}

#[tauri::command]
pub fn finance_upsert_transaction(
    app: AppHandle,
    state: State<'_, AppState>,
    input: UpsertTransactionInput,
) -> CmdResult<String> {
    let posted = input
        .posted_at
        .unwrap_or_else(|| Utc::now().to_rfc3339());
    let category = input.category.unwrap_or_default();
    let memo = input.memo.unwrap_or_default();
    let id = if let Some(existing) = input.id.filter(|s| !s.is_empty()) {
        state.db.with_conn(|conn| {
            let (old_account, old_amount): (String, f64) = conn.query_row(
                "SELECT account_id, amount FROM finance_transaction WHERE id = ?1",
                rusqlite::params![existing],
                |r| Ok((r.get(0)?, r.get(1)?)),
            )?;
            conn.execute(
                "UPDATE finance_transaction
                 SET account_id = ?1, posted_at = ?2, amount = ?3, payee = ?4, category = ?5, memo = ?6
                 WHERE id = ?7",
                rusqlite::params![
                    input.account_id,
                    posted,
                    input.amount,
                    input.payee,
                    category,
                    memo,
                    existing
                ],
            )?;
            if old_account == input.account_id {
                let delta = input.amount - old_amount;
                if delta.abs() > f64::EPSILON {
                    conn.execute(
                        "UPDATE finance_account SET balance = balance + ?1 WHERE id = ?2",
                        rusqlite::params![delta, input.account_id],
                    )?;
                }
            } else {
                conn.execute(
                    "UPDATE finance_account SET balance = balance - ?1 WHERE id = ?2",
                    rusqlite::params![old_amount, old_account],
                )?;
                conn.execute(
                    "UPDATE finance_account SET balance = balance + ?1 WHERE id = ?2",
                    rusqlite::params![input.amount, input.account_id],
                )?;
            }
            Ok(())
        })?;
        existing
    } else {
        let id = Uuid::new_v4().to_string();
        state.db.with_conn(|conn| {
            conn.execute(
                "INSERT INTO finance_transaction
                 (id, account_id, posted_at, amount, payee, category, memo, external_id)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, NULL)",
                rusqlite::params![
                    id,
                    input.account_id,
                    posted,
                    input.amount,
                    input.payee,
                    category,
                    memo
                ],
            )?;
            conn.execute(
                "UPDATE finance_account SET balance = balance + ?1 WHERE id = ?2",
                rusqlite::params![input.amount, input.account_id],
            )?;
            Ok(())
        })?;
        id
    };
    bump(&app, &state, "finance")?;
    Ok(id)
}

#[tauri::command]
pub fn documents_upsert_vault_doc(
    app: AppHandle,
    state: State<'_, AppState>,
    input: UpsertVaultDocInput,
) -> CmdResult<String> {
    let id = Uuid::new_v4().to_string();
    let now = Utc::now().to_rfc3339();
    state.db.with_conn(|conn| {
        conn.execute(
            "INSERT INTO vault_document
             (id, title, relative_path, mime_type, category, parent_folder_id, course_id,
              tags_json, file_size, created_at, updated_at, sort_order, is_folder)
             VALUES (?1, ?2, '', ?3, ?4, ?5, NULL, '[]', 0, ?6, ?6, 0, 0)",
            rusqlite::params![
                id,
                input.title,
                input.mime_type.unwrap_or_else(|| "application/pdf".into()),
                input.category.unwrap_or_else(|| "general".into()),
                input.parent_folder_id,
                now
            ],
        )?;
        Ok(())
    })?;
    bump(&app, &state, "vault")?;
    Ok(id)
}

#[tauri::command]
pub fn profile_upsert_identity(
    app: AppHandle,
    state: State<'_, AppState>,
    input: UpsertProfileInput,
) -> CmdResult<String> {
    let now = Utc::now().to_rfc3339();
    let id = state.db.with_conn(|conn| {
        let existing: Option<String> = conn
            .query_row(
                "SELECT id FROM profile ORDER BY updated_at DESC LIMIT 1",
                [],
                |r| r.get(0),
            )
            .ok();
        if let Some(id) = existing {
            conn.execute(
                "UPDATE profile SET full_name = ?1, email = ?2, university_name = ?3, major = ?4,
                 graduation_year = ?5, updated_at = ?6 WHERE id = ?7",
                rusqlite::params![
                    input.full_name,
                    input.email.unwrap_or_default(),
                    input.university_name.unwrap_or_default(),
                    input.major.unwrap_or_default(),
                    input.graduation_year,
                    now,
                    id
                ],
            )?;
            Ok(id)
        } else {
            let id = Uuid::new_v4().to_string();
            conn.execute(
                "INSERT INTO profile
                 (id, full_name, email, phone, university_name, major, graduation_year, created_at, updated_at)
                 VALUES (?1, ?2, ?3, '', ?4, ?5, ?6, ?7, ?7)",
                rusqlite::params![
                    id,
                    input.full_name,
                    input.email.unwrap_or_default(),
                    input.university_name.unwrap_or_default(),
                    input.major.unwrap_or_default(),
                    input.graduation_year,
                    now
                ],
            )?;
            Ok(id)
        }
    })?;
    bump(&app, &state, "profile")?;
    Ok(id)
}

#[tauri::command]
pub fn profile_upsert_experience(
    app: AppHandle,
    state: State<'_, AppState>,
    input: UpsertExperienceInput,
) -> CmdResult<String> {
    let summary = input.summary.unwrap_or_default();
    let id = if let Some(existing) = input.id.filter(|s| !s.is_empty()) {
        state.db.with_conn(|conn| {
            conn.execute(
                "UPDATE experience
                 SET title = ?1, organization = ?2, start_date = ?3, end_date = ?4, summary = ?5
                 WHERE id = ?6",
                rusqlite::params![
                    input.title,
                    input.organization,
                    input.start_date,
                    input.end_date,
                    summary,
                    existing
                ],
            )?;
            Ok(())
        })?;
        existing
    } else {
        let id = Uuid::new_v4().to_string();
        state.db.with_conn(|conn| {
            let profile_id: String = conn
                .query_row(
                    "SELECT id FROM profile ORDER BY updated_at DESC LIMIT 1",
                    [],
                    |r| r.get(0),
                )
                .map_err(|_| anyhow::anyhow!("Create a profile identity before adding experience"))?;
            conn.execute(
                "INSERT INTO experience
                 (id, profile_id, title, organization, start_date, end_date, summary, sort_order)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, 0)",
                rusqlite::params![
                    id,
                    profile_id,
                    input.title,
                    input.organization,
                    input.start_date,
                    input.end_date,
                    summary
                ],
            )?;
            Ok(())
        })?;
        id
    };
    bump(&app, &state, "profile")?;
    Ok(id)
}

#[tauri::command]
pub fn finance_upsert_goal(
    app: AppHandle,
    state: State<'_, AppState>,
    input: UpsertGoalInput,
) -> CmdResult<String> {
    let current_amount = input.current_amount.unwrap_or(0.0);
    let notes = input.notes.unwrap_or_default();
    let sort_order = input.sort_order.unwrap_or(0);
    let id = if let Some(existing) = input.id.filter(|s| !s.is_empty()) {
        state.db.with_conn(|conn| {
            conn.execute(
                "UPDATE finance_goal
                 SET name = ?1, target_amount = ?2, current_amount = ?3, deadline = ?4,
                     notes = ?5, sort_order = ?6
                 WHERE id = ?7",
                rusqlite::params![
                    input.name,
                    input.target_amount,
                    current_amount,
                    input.deadline,
                    notes,
                    sort_order,
                    existing
                ],
            )?;
            Ok(())
        })?;
        existing
    } else {
        let id = Uuid::new_v4().to_string();
        state.db.with_conn(|conn| {
            conn.execute(
                "INSERT INTO finance_goal
                 (id, name, target_amount, current_amount, deadline, notes, sort_order)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
                rusqlite::params![
                    id,
                    input.name,
                    input.target_amount,
                    current_amount,
                    input.deadline,
                    notes,
                    sort_order
                ],
            )?;
            Ok(())
        })?;
        id
    };
    bump(&app, &state, "finance")?;
    Ok(id)
}

#[tauri::command]
pub fn finance_upsert_inventory_item(
    app: AppHandle,
    state: State<'_, AppState>,
    input: UpsertInventoryItemInput,
) -> CmdResult<String> {
    let category = input.category.unwrap_or_default();
    let value = input.value.unwrap_or(0.0);
    let notes = input.notes.unwrap_or_default();
    let sort_order = input.sort_order.unwrap_or(0);
    let id = if let Some(existing) = input.id.filter(|s| !s.is_empty()) {
        state.db.with_conn(|conn| {
            conn.execute(
                "UPDATE finance_inventory_item
                 SET name = ?1, category = ?2, purchase_date = ?3, value = ?4, notes = ?5, sort_order = ?6
                 WHERE id = ?7",
                rusqlite::params![
                    input.name,
                    category,
                    input.purchase_date,
                    value,
                    notes,
                    sort_order,
                    existing
                ],
            )?;
            Ok(())
        })?;
        existing
    } else {
        let id = Uuid::new_v4().to_string();
        state.db.with_conn(|conn| {
            conn.execute(
                "INSERT INTO finance_inventory_item
                 (id, name, category, purchase_date, value, notes, sort_order)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
                rusqlite::params![
                    id,
                    input.name,
                    category,
                    input.purchase_date,
                    value,
                    notes,
                    sort_order
                ],
            )?;
            Ok(())
        })?;
        id
    };
    bump(&app, &state, "finance")?;
    Ok(id)
}

#[tauri::command]
pub fn finance_upsert_receipt(
    app: AppHandle,
    state: State<'_, AppState>,
    input: UpsertReceiptInput,
) -> CmdResult<String> {
    let merchant = input.merchant.unwrap_or_default();
    let amount = input.amount.unwrap_or(0.0);
    let category = input.category.unwrap_or_default();
    let notes = input.notes.unwrap_or_default();
    let sort_order = input.sort_order.unwrap_or(0);
    let vault_doc_id = input.vault_doc_id.filter(|s| !s.is_empty());
    let id = if let Some(existing) = input.id.filter(|s| !s.is_empty()) {
        state.db.with_conn(|conn| {
            conn.execute(
                "UPDATE finance_receipt
                 SET title = ?1, merchant = ?2, amount = ?3, purchased_at = ?4, category = ?5,
                     notes = ?6, vault_doc_id = ?7, sort_order = ?8
                 WHERE id = ?9",
                rusqlite::params![
                    input.title,
                    merchant,
                    amount,
                    input.purchased_at,
                    category,
                    notes,
                    vault_doc_id,
                    sort_order,
                    existing
                ],
            )?;
            Ok(())
        })?;
        existing
    } else {
        let id = Uuid::new_v4().to_string();
        state.db.with_conn(|conn| {
            conn.execute(
                "INSERT INTO finance_receipt
                 (id, title, merchant, amount, purchased_at, category, notes, vault_doc_id, sort_order)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)",
                rusqlite::params![
                    id,
                    input.title,
                    merchant,
                    amount,
                    input.purchased_at,
                    category,
                    notes,
                    vault_doc_id,
                    sort_order
                ],
            )?;
            Ok(())
        })?;
        id
    };
    bump(&app, &state, "finance")?;
    Ok(id)
}

#[tauri::command]
pub fn finance_upsert_budget(
    app: AppHandle,
    state: State<'_, AppState>,
    input: UpsertBudgetInput,
) -> CmdResult<String> {
    let category = input.category.unwrap_or_default();
    let period = input.period.unwrap_or_else(|| "monthly".into());
    let id = if let Some(existing) = input.id.filter(|s| !s.is_empty()) {
        state.db.with_conn(|conn| {
            conn.execute(
                "UPDATE finance_budget
                 SET name = ?1, category = ?2, amount = ?3, period = ?4
                 WHERE id = ?5",
                rusqlite::params![input.name, category, input.amount, period, existing],
            )?;
            Ok(())
        })?;
        existing
    } else {
        let id = Uuid::new_v4().to_string();
        state.db.with_conn(|conn| {
            conn.execute(
                "INSERT INTO finance_budget (id, name, category, amount, period)
                 VALUES (?1, ?2, ?3, ?4, ?5)",
                rusqlite::params![id, input.name, category, input.amount, period],
            )?;
            Ok(())
        })?;
        id
    };
    bump(&app, &state, "finance")?;
    Ok(id)
}

#[tauri::command]
pub fn finance_upsert_recurring(
    app: AppHandle,
    state: State<'_, AppState>,
    input: UpsertRecurringInput,
) -> CmdResult<String> {
    let cadence = input.cadence.unwrap_or_else(|| "monthly".into());
    let category = input.category.unwrap_or_default();
    let id = if let Some(existing) = input.id.filter(|s| !s.is_empty()) {
        state.db.with_conn(|conn| {
            conn.execute(
                "UPDATE finance_recurring
                 SET account_id = ?1, title = ?2, amount = ?3, cadence = ?4, next_due = ?5, category = ?6
                 WHERE id = ?7",
                rusqlite::params![
                    input.account_id,
                    input.title,
                    input.amount,
                    cadence,
                    input.next_due,
                    category,
                    existing
                ],
            )?;
            Ok(())
        })?;
        existing
    } else {
        let id = Uuid::new_v4().to_string();
        state.db.with_conn(|conn| {
            conn.execute(
                "INSERT INTO finance_recurring
                 (id, account_id, title, amount, cadence, next_due, category)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
                rusqlite::params![
                    id,
                    input.account_id,
                    input.title,
                    input.amount,
                    cadence,
                    input.next_due,
                    category
                ],
            )?;
            Ok(())
        })?;
        id
    };
    bump(&app, &state, "finance")?;
    Ok(id)
}

fn advance_recurring_due(cadence: &str, current: &str) -> Option<String> {
    let date = chrono::DateTime::parse_from_rfc3339(current)
        .ok()
        .map(|d| d.with_timezone(&Utc))
        .or_else(|| {
            chrono::NaiveDate::parse_from_str(current, "%Y-%m-%d")
                .ok()
                .and_then(|d| d.and_hms_opt(12, 0, 0))
                .map(|dt| dt.and_utc())
        })?;
    let next = match cadence.to_ascii_lowercase().as_str() {
        "weekly" => date + Duration::days(7),
        "yearly" | "annual" => date + Duration::days(365),
        _ => date + Duration::days(30),
    };
    Some(next.to_rfc3339())
}

#[derive(Debug, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct FinanceRunRecurringResult {
    pub created: i64,
    pub skipped: i64,
}

#[tauri::command]
pub fn finance_run_recurring_due(
    app: AppHandle,
    state: State<'_, AppState>,
) -> CmdResult<FinanceRunRecurringResult> {
    let now = Utc::now().to_rfc3339();
    let mut created = 0i64;
    let mut skipped = 0i64;

    state.db.with_conn(|conn| {
        let mut stmt = conn.prepare(
            "SELECT id, account_id, title, amount, cadence, next_due, category
             FROM finance_recurring
             WHERE next_due IS NOT NULL AND TRIM(next_due) != '' AND next_due <= ?1",
        )?;
        let rows: Vec<(String, Option<String>, String, f64, String, String, String)> = stmt
            .query_map(rusqlite::params![now], |r| {
                Ok((
                    r.get(0)?,
                    r.get(1)?,
                    r.get(2)?,
                    r.get(3)?,
                    r.get(4)?,
                    r.get(5)?,
                    r.get(6)?,
                ))
            })?
            .filter_map(|r| r.ok())
            .collect();

        for (id, account_id, title, amount, cadence, next_due, category) in rows {
            let Some(account_id) = account_id.filter(|s| !s.is_empty()) else {
                skipped += 1;
                continue;
            };
            let tx_id = Uuid::new_v4().to_string();
            conn.execute(
                "INSERT INTO finance_transaction
                 (id, account_id, posted_at, amount, payee, category, memo, external_id)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)",
                rusqlite::params![
                    tx_id,
                    account_id,
                    now,
                    amount,
                    title,
                    category,
                    "Recurring charge",
                    id
                ],
            )?;
            conn.execute(
                "UPDATE finance_account SET balance = balance + ?1 WHERE id = ?2",
                rusqlite::params![amount, account_id],
            )?;
            let advanced = advance_recurring_due(&cadence, &next_due).unwrap_or(next_due);
            conn.execute(
                "UPDATE finance_recurring SET next_due = ?1 WHERE id = ?2",
                rusqlite::params![advanced, id],
            )?;
            created += 1;
        }
        Ok(())
    })?;

    bump(&app, &state, "finance")?;
    Ok(FinanceRunRecurringResult { created, skipped })
}

#[tauri::command]
pub fn finance_mark_due_paid(
    app: AppHandle,
    state: State<'_, AppState>,
    id: String,
) -> CmdResult<()> {
    state.db.with_conn(|conn| {
        conn.execute(
            "UPDATE finance_due SET is_paid = 1 WHERE id = ?1",
            rusqlite::params![id],
        )?;
        Ok(())
    })?;
    bump(&app, &state, "finance")?;
    Ok(())
}

#[tauri::command]
pub fn finance_delete_recurring(
    app: AppHandle,
    state: State<'_, AppState>,
    id: String,
) -> CmdResult<()> {
    state.db.with_conn(|conn| {
        conn.execute(
            "DELETE FROM finance_recurring WHERE id = ?1",
            rusqlite::params![id],
        )?;
        Ok(())
    })?;
    bump(&app, &state, "finance")?;
    Ok(())
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ImportCsvInput {
    pub account_id: String,
    pub csv_text: String,
}

#[tauri::command]
pub fn finance_import_transactions_csv(
    app: AppHandle,
    state: State<'_, AppState>,
    input: ImportCsvInput,
) -> CmdResult<i64> {
    let mut imported = 0i64;
    let mut balance_delta = 0.0f64;
    state.db.with_conn(|conn| {
        for (idx, raw) in input.csv_text.lines().enumerate() {
            let line = raw.trim();
            if line.is_empty() {
                continue;
            }
            if idx == 0 && line.to_ascii_lowercase().contains("amount") {
                continue; // header
            }
            let cols: Vec<&str> = line.split(',').map(str::trim).collect();
            if cols.len() < 3 {
                continue;
            }
            // Formats: date,amount,payee[,category]
            // or amount,payee,date
            let (posted, amount_s, payee, category) = if cols[1].parse::<f64>().is_ok() {
                (
                    cols[0].to_string(),
                    cols[1],
                    cols[2].to_string(),
                    cols.get(3).unwrap_or(&"").to_string(),
                )
            } else if cols[0].parse::<f64>().is_ok() {
                (
                    cols.get(2).unwrap_or(&"").to_string(),
                    cols[0],
                    cols[1].to_string(),
                    cols.get(3).unwrap_or(&"").to_string(),
                )
            } else {
                continue;
            };
            let Ok(amount) = amount_s.parse::<f64>() else {
                continue;
            };
            let posted_at = if posted.is_empty() {
                Utc::now().to_rfc3339()
            } else if posted.contains('T') {
                posted
            } else {
                format!("{posted}T12:00:00Z")
            };
            let id = Uuid::new_v4().to_string();
            conn.execute(
                "INSERT INTO finance_transaction
                 (id, account_id, posted_at, amount, payee, category, memo, external_id)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, 'csv-import', NULL)",
                rusqlite::params![id, input.account_id, posted_at, amount, payee, category],
            )?;
            balance_delta += amount;
            imported += 1;
        }
        if imported > 0 {
            conn.execute(
                "UPDATE finance_account SET balance = balance + ?1 WHERE id = ?2",
                rusqlite::params![balance_delta, input.account_id],
            )?;
        }
        Ok(())
    })?;
    bump(&app, &state, "finance")?;
    Ok(imported)
}

#[tauri::command]
pub fn finance_import_transactions_csv_path(
    app: AppHandle,
    state: State<'_, AppState>,
    account_id: String,
    path: String,
) -> CmdResult<i64> {
    let csv_text = std::fs::read_to_string(&path).map_err(anyhow::Error::from)?;
    finance_import_transactions_csv(
        app,
        state,
        ImportCsvInput {
            account_id,
            csv_text,
        },
    )
}

#[tauri::command]
pub fn profile_upsert_achievement(
    app: AppHandle,
    state: State<'_, AppState>,
    input: UpsertAchievementInput,
) -> CmdResult<String> {
    let issuer = input.issuer.unwrap_or_default();
    let notes = input.notes.unwrap_or_default();
    let id = if let Some(existing) = input.id.filter(|s| !s.is_empty()) {
        state.db.with_conn(|conn| {
            conn.execute(
                "UPDATE achievement SET title = ?1, issuer = ?2, notes = ?3 WHERE id = ?4",
                rusqlite::params![input.title, issuer, notes, existing],
            )?;
            Ok(())
        })?;
        existing
    } else {
        let id = Uuid::new_v4().to_string();
        state.db.with_conn(|conn| {
            let profile_id: String = conn
                .query_row(
                    "SELECT id FROM profile ORDER BY updated_at DESC LIMIT 1",
                    [],
                    |r| r.get(0),
                )
                .map_err(|_| anyhow::anyhow!("Create a profile identity before adding achievements"))?;
            conn.execute(
                "INSERT INTO achievement (id, profile_id, title, issuer, date_received, notes)
                 VALUES (?1, ?2, ?3, ?4, NULL, ?5)",
                rusqlite::params![id, profile_id, input.title, issuer, notes],
            )?;
            Ok(())
        })?;
        id
    };
    bump(&app, &state, "profile")?;
    Ok(id)
}

#[tauri::command]
pub fn academics_delete_course(
    app: AppHandle,
    state: State<'_, AppState>,
    id: String,
) -> CmdResult<()> {
    state.db.with_conn(|conn| {
        conn.execute("DELETE FROM planner_course WHERE id = ?1", rusqlite::params![id])?;
        Ok(())
    })?;
    bump(&app, &state, "planner")?;
    Ok(())
}

#[tauri::command]
pub fn calendar_delete_event(
    app: AppHandle,
    state: State<'_, AppState>,
    id: String,
) -> CmdResult<()> {
    state.db.with_conn(|conn| {
        conn.execute("DELETE FROM calendar_event WHERE id = ?1", rusqlite::params![id])?;
        Ok(())
    })?;
    bump(&app, &state, "calendar")?;
    Ok(())
}

#[tauri::command]
pub fn calendar_delete_task(
    app: AppHandle,
    state: State<'_, AppState>,
    id: String,
) -> CmdResult<()> {
    state.db.with_conn(|conn| {
        conn.execute("DELETE FROM planner_task WHERE id = ?1", rusqlite::params![id])?;
        Ok(())
    })?;
    bump(&app, &state, "planner")?;
    bump(&app, &state, "calendar")?;
    Ok(())
}

#[tauri::command]
pub fn career_delete_application(
    app: AppHandle,
    state: State<'_, AppState>,
    id: String,
) -> CmdResult<()> {
    state.db.with_conn(|conn| {
        conn.execute("DELETE FROM job_application WHERE id = ?1", rusqlite::params![id])?;
        Ok(())
    })?;
    bump(&app, &state, "career")?;
    Ok(())
}

#[tauri::command]
pub fn finance_delete_transaction(
    app: AppHandle,
    state: State<'_, AppState>,
    id: String,
) -> CmdResult<()> {
    state.db.with_conn(|conn| {
        let row: Option<(String, f64)> = match conn.query_row(
            "SELECT account_id, amount FROM finance_transaction WHERE id = ?1",
            rusqlite::params![id],
            |r| Ok((r.get(0)?, r.get(1)?)),
        ) {
            Ok(v) => Some(v),
            Err(rusqlite::Error::QueryReturnedNoRows) => None,
            Err(e) => return Err(e.into()),
        };
        if let Some((account_id, amount)) = row {
            conn.execute(
                "DELETE FROM finance_transaction WHERE id = ?1",
                rusqlite::params![id],
            )?;
            conn.execute(
                "UPDATE finance_account SET balance = balance - ?1 WHERE id = ?2",
                rusqlite::params![amount, account_id],
            )?;
        }
        Ok(())
    })?;
    bump(&app, &state, "finance")?;
    Ok(())
}

#[tauri::command]
pub fn academics_delete_semester(
    app: AppHandle,
    state: State<'_, AppState>,
    id: String,
) -> CmdResult<()> {
    state.db.with_conn(|conn| {
        conn.execute(
            "DELETE FROM planner_course WHERE semester_id = ?1",
            rusqlite::params![id],
        )?;
        conn.execute(
            "DELETE FROM planner_semester WHERE id = ?1",
            rusqlite::params![id],
        )?;
        Ok(())
    })?;
    bump(&app, &state, "planner")?;
    Ok(())
}

#[tauri::command]
pub fn finance_delete_account(
    app: AppHandle,
    state: State<'_, AppState>,
    id: String,
) -> CmdResult<()> {
    state.db.with_conn(|conn| {
        conn.execute(
            "DELETE FROM finance_transaction WHERE account_id = ?1",
            rusqlite::params![id],
        )?;
        conn.execute(
            "DELETE FROM finance_account WHERE id = ?1",
            rusqlite::params![id],
        )?;
        Ok(())
    })?;
    bump(&app, &state, "finance")?;
    Ok(())
}

#[tauri::command]
pub fn finance_delete_budget(
    app: AppHandle,
    state: State<'_, AppState>,
    id: String,
) -> CmdResult<()> {
    state.db.with_conn(|conn| {
        conn.execute(
            "DELETE FROM finance_budget WHERE id = ?1",
            rusqlite::params![id],
        )?;
        Ok(())
    })?;
    bump(&app, &state, "finance")?;
    Ok(())
}

#[tauri::command]
pub fn finance_delete_goal(
    app: AppHandle,
    state: State<'_, AppState>,
    id: String,
) -> CmdResult<()> {
    state.db.with_conn(|conn| {
        conn.execute(
            "DELETE FROM finance_goal WHERE id = ?1",
            rusqlite::params![id],
        )?;
        Ok(())
    })?;
    bump(&app, &state, "finance")?;
    Ok(())
}

#[tauri::command]
pub fn finance_delete_inventory_item(
    app: AppHandle,
    state: State<'_, AppState>,
    id: String,
) -> CmdResult<()> {
    state.db.with_conn(|conn| {
        conn.execute(
            "DELETE FROM finance_inventory_item WHERE id = ?1",
            rusqlite::params![id],
        )?;
        Ok(())
    })?;
    bump(&app, &state, "finance")?;
    Ok(())
}

#[tauri::command]
pub fn finance_delete_receipt(
    app: AppHandle,
    state: State<'_, AppState>,
    id: String,
) -> CmdResult<()> {
    state.db.with_conn(|conn| {
        conn.execute(
            "DELETE FROM finance_receipt WHERE id = ?1",
            rusqlite::params![id],
        )?;
        Ok(())
    })?;
    bump(&app, &state, "finance")?;
    Ok(())
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UpsertFinanceHoldingInput {
    pub id: Option<String>,
    pub asset_type: String,
    pub symbol: String,
    pub name: Option<String>,
    pub quantity: f64,
    pub price_per_unit: f64,
}

#[tauri::command]
pub fn finance_upsert_holding(
    app: AppHandle,
    state: State<'_, AppState>,
    input: UpsertFinanceHoldingInput,
) -> CmdResult<String> {
    let id = input.id.unwrap_or_else(|| Uuid::new_v4().to_string());
    let now = Utc::now().to_rfc3339();
    state.db.with_conn(|conn| {
        conn.execute(
            "INSERT INTO finance_holding (id, asset_type, symbol, name, quantity, price_per_unit, updated_at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
             ON CONFLICT(id) DO UPDATE SET
               asset_type = excluded.asset_type,
               symbol = excluded.symbol,
               name = excluded.name,
               quantity = excluded.quantity,
               price_per_unit = excluded.price_per_unit,
               updated_at = excluded.updated_at",
            rusqlite::params![
                id,
                input.asset_type,
                input.symbol,
                input.name.unwrap_or_default(),
                input.quantity,
                input.price_per_unit,
                now
            ],
        )?;
        Ok(())
    })?;
    bump(&app, &state, "finance")?;
    Ok(id)
}

#[tauri::command]
pub fn finance_delete_holding(
    app: AppHandle,
    state: State<'_, AppState>,
    id: String,
) -> CmdResult<()> {
    state.db.with_conn(|conn| {
        conn.execute(
            "DELETE FROM finance_holding WHERE id = ?1",
            rusqlite::params![id],
        )?;
        Ok(())
    })?;
    bump(&app, &state, "finance")?;
    Ok(())
}

#[tauri::command]
pub fn profile_delete_experience(
    app: AppHandle,
    state: State<'_, AppState>,
    id: String,
) -> CmdResult<()> {
    state.db.with_conn(|conn| {
        conn.execute("DELETE FROM experience WHERE id = ?1", rusqlite::params![id])?;
        Ok(())
    })?;
    bump(&app, &state, "profile")?;
    Ok(())
}

#[tauri::command]
pub fn profile_delete_achievement(
    app: AppHandle,
    state: State<'_, AppState>,
    id: String,
) -> CmdResult<()> {
    state.db.with_conn(|conn| {
        conn.execute("DELETE FROM achievement WHERE id = ?1", rusqlite::params![id])?;
        Ok(())
    })?;
    bump(&app, &state, "profile")?;
    Ok(())
}

fn collect_vault_descendant_ids(
    conn: &rusqlite::Connection,
    root_id: &str,
) -> Result<Vec<String>, rusqlite::Error> {
    let mut result = Vec::new();
    let mut queue = vec![root_id.to_string()];
    while let Some(parent_id) = queue.pop() {
        let mut stmt = conn.prepare(
            "SELECT id, is_folder FROM vault_document WHERE parent_folder_id = ?1",
        )?;
        let rows = stmt.query_map(rusqlite::params![parent_id], |r| {
            Ok((r.get::<_, String>(0)?, r.get::<_, i32>(1)?))
        })?;
        for row in rows {
            let (child_id, is_folder) = row?;
            result.push(child_id.clone());
            if is_folder != 0 {
                queue.push(child_id);
            }
        }
    }
    Ok(result)
}

fn delete_vault_row_and_file(
    conn: &rusqlite::Connection,
    vault_dir: &std::path::Path,
    id: &str,
) -> Result<(), rusqlite::Error> {
    let relative: Option<String> = match conn.query_row(
        "SELECT relative_path FROM vault_document WHERE id = ?1",
        rusqlite::params![id],
        |r| r.get(0),
    ) {
        Ok(v) => Some(v),
        Err(rusqlite::Error::QueryReturnedNoRows) => return Ok(()),
        Err(e) => return Err(e),
    };
    conn.execute(
        "DELETE FROM vault_document WHERE id = ?1",
        rusqlite::params![id],
    )?;
    if let Some(rel) = relative.filter(|r| !r.is_empty()) {
        let path = vault_dir.join(rel);
        let _ = std::fs::remove_file(path);
    }
    Ok(())
}

#[tauri::command]
pub fn documents_delete_vault_doc(
    app: AppHandle,
    state: State<'_, AppState>,
    id: String,
    cascade: Option<bool>,
) -> CmdResult<()> {
    let cascade = cascade.unwrap_or(false);
    let vault_dir = state.paths.vault_dir.clone();
    state.db.with_conn(|conn| {
        let (is_folder, child_count): (i32, i64) = match conn.query_row(
            "SELECT is_folder,
                    (SELECT COUNT(*) FROM vault_document WHERE parent_folder_id = ?1)
             FROM vault_document WHERE id = ?1",
            rusqlite::params![id, id],
            |r| Ok((r.get(0)?, r.get(1)?)),
        ) {
            Ok(v) => v,
            Err(rusqlite::Error::QueryReturnedNoRows) => {
                return Err(anyhow::anyhow!("Vault item not found").into());
            }
            Err(e) => return Err(e.into()),
        };

        if is_folder != 0 && child_count > 0 && !cascade {
            return Err(anyhow::anyhow!(
                "Folder contains {child_count} item(s); confirm cascade delete"
            )
            .into());
        }

        let mut ids_to_delete = if cascade && is_folder != 0 {
            collect_vault_descendant_ids(conn, &id)?
        } else {
            Vec::new()
        };
        ids_to_delete.push(id);
        for del_id in ids_to_delete {
            delete_vault_row_and_file(conn, &vault_dir, &del_id)?;
        }
        Ok(())
    })?;
    bump(&app, &state, "vault")?;
    Ok(())
}

/// Delete a folder and all nested items (files + subfolders).
#[tauri::command]
pub fn documents_delete_folder_cascade(
    app: AppHandle,
    state: State<'_, AppState>,
    id: String,
) -> CmdResult<()> {
    documents_delete_vault_doc(app, state, id, Some(true))
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ResumeMatchInput {
    pub resume_text: String,
    pub job_text: String,
}

#[tauri::command]
pub fn career_resume_keyword_match(
    state: State<'_, AppState>,
    input: ResumeMatchInput,
) -> CmdResult<serde_json::Value> {
    fn tokens(s: &str) -> std::collections::HashSet<String> {
        s.split(|c: char| !c.is_alphanumeric())
            .map(|t| t.to_ascii_lowercase())
            .filter(|t| t.len() > 2)
            .collect()
    }
    let resume = tokens(&input.resume_text);
    let job = tokens(&input.job_text);
    if job.is_empty() {
        return Ok(serde_json::json!({
            "score": 0.0,
            "matched": [],
            "missing": [],
        }));
    }
    let mut matched = Vec::new();
    let mut missing = Vec::new();
    for term in &job {
        if resume.contains(term) {
            matched.push(term.clone());
        } else {
            missing.push(term.clone());
        }
    }
    matched.sort();
    missing.sort();
    let score = matched.len() as f64 / job.len() as f64;
    let now = Utc::now().to_rfc3339();
    let _ = state.db.with_conn(|conn| {
        conn.execute(
            "INSERT INTO app_settings (key, value, updated_at)
             VALUES ('career.lastMatchScore', ?1, ?2)
             ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at",
            rusqlite::params![
                serde_json::json!({ "score": score, "at": now }).to_string(),
                now
            ],
        )?;
        Ok(())
    });
    Ok(serde_json::json!({
        "score": score,
        "matched": matched.into_iter().take(40).collect::<Vec<_>>(),
        "missing": missing.into_iter().take(40).collect::<Vec<_>>(),
    }))
}

#[tauri::command]
pub fn demo_seed_sample_data(app: AppHandle, state: State<'_, AppState>) -> CmdResult<()> {
    let year = Utc::now().format("%Y").to_string().parse::<i64>().unwrap_or(2026);
    let semester_id = Uuid::new_v4().to_string();
    let now = Utc::now();
    let now_s = now.to_rfc3339();

    state.db.with_conn(|conn| {
        conn.execute("UPDATE planner_semester SET is_current = 0", [])?;
        conn.execute(
            "INSERT INTO planner_semester (id, plan_id, year, season, label, is_current, sort_order)
             VALUES (?1, NULL, ?2, 'Fall', ?3, 1, 0)",
            rusqlite::params![semester_id, year, format!("Fall {year}")],
        )?;
        for (code, title, credits, status, grade) in [
            ("CS 101", "Intro to Computer Science", 3.0, "in_progress", None),
            ("MATH 201", "Calculus II", 4.0, "planned", None),
            ("ENG 110", "College Writing", 3.0, "completed", Some("A-")),
            ("HIST 120", "World History", 3.0, "completed", Some("B+")),
        ] {
            conn.execute(
                "INSERT INTO planner_course
                 (id, semester_id, catalog_course_id, code, title, credits, grade, status, sort_order)
                 VALUES (?1, ?2, NULL, ?3, ?4, ?5, ?6, ?7, 0)",
                rusqlite::params![
                    Uuid::new_v4().to_string(),
                    semester_id,
                    code,
                    title,
                    credits,
                    grade,
                    status
                ],
            )?;
        }

        conn.execute(
            "INSERT INTO calendar_event
             (id, title, start_at, end_at, all_day, location, notes, provider, provider_event_id,
              semester_id, course_id, color_hex, created_at, updated_at)
             VALUES (?1, 'Advisor meeting', ?2, ?3, 0, 'Student Center', '', 'local', NULL, NULL, NULL, NULL, ?4, ?4)",
            rusqlite::params![
                Uuid::new_v4().to_string(),
                (now + Duration::days(2)).to_rfc3339(),
                (now + Duration::days(2) + Duration::hours(1)).to_rfc3339(),
                now_s
            ],
        )?;
        conn.execute(
            "INSERT INTO planner_task
             (id, semester_id, course_id, title, due_at, is_complete, notes, lms_item_id)
             VALUES (?1, NULL, NULL, 'Submit CS 101 lab', ?2, 0, '', NULL)",
            rusqlite::params![
                Uuid::new_v4().to_string(),
                (now + Duration::days(5)).to_rfc3339()
            ],
        )?;

        for (company, role, status) in [
            ("Acme Robotics", "Software Intern", "interested"),
            ("Northwind Health", "Data Analyst", "applied"),
            ("Brightpath Labs", "Research Assistant", "interviewing"),
        ] {
            conn.execute(
                "INSERT INTO job_application
                 (id, company, role_title, status, location, url, applied_at, notes, salary_text,
                  sort_order, created_at, updated_at)
                 VALUES (?1, ?2, ?3, ?4, 'Remote', '', NULL, '', '', 0, ?5, ?5)",
                rusqlite::params![Uuid::new_v4().to_string(), company, role, status, now_s],
            )?;
        }
        for (company, title, location, url) in [
            (
                "Riverdale Systems",
                "Frontend Engineer Intern",
                "New York, NY",
                "https://example.com/jobs/fe-intern",
            ),
            (
                "Cascade Analytics",
                "ML Research Intern",
                "Remote",
                "https://example.com/jobs/ml-intern",
            ),
            (
                "Harbor Financial",
                "Software Engineer (New Grad)",
                "Boston, MA",
                "https://example.com/jobs/ng-swe",
            ),
        ] {
            conn.execute(
                "INSERT INTO workday_job_posting
                 (id, company, title, location, url, posted_at, tracked_application_id, raw_json)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, NULL, '{}')",
                rusqlite::params![
                    Uuid::new_v4().to_string(),
                    company,
                    title,
                    location,
                    url,
                    now_s
                ],
            )?;
        }

        let checking_id = Uuid::new_v4().to_string();
        conn.execute(
            "INSERT INTO finance_account
             (id, name, institution, account_type, currency, balance, is_hidden, sort_order)
             VALUES (?1, 'Campus Checking', 'First Student Bank', 'checking', 'USD', 1842.55, 0, 0)",
            rusqlite::params![checking_id],
        )?;
        conn.execute(
            "INSERT INTO finance_account
             (id, name, institution, account_type, currency, balance, is_hidden, sort_order)
             VALUES (?1, 'Emergency Savings', 'First Student Bank', 'savings', 'USD', 3200.00, 0, 1)",
            rusqlite::params![Uuid::new_v4().to_string()],
        )?;
        for (days_ago, amount, payee, category) in [
            (1i64, -42.18, "Campus Cafe", "Food"),
            (3, -89.00, "Bookstore", "School"),
            (5, 500.00, "Payroll Deposit", "Income"),
            (8, -12.50, "Transit Pass", "Transport"),
        ] {
            conn.execute(
                "INSERT INTO finance_transaction
                 (id, account_id, posted_at, amount, payee, category, memo, external_id)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, '', NULL)",
                rusqlite::params![
                    Uuid::new_v4().to_string(),
                    checking_id,
                    (now - Duration::days(days_ago)).to_rfc3339(),
                    amount,
                    payee,
                    category
                ],
            )?;
        }

        conn.execute(
            "INSERT INTO vault_document
             (id, title, relative_path, mime_type, category, parent_folder_id, course_id,
              tags_json, file_size, created_at, updated_at, sort_order)
             VALUES (?1, 'Fall Syllabus — CS 101', '', 'application/pdf', 'syllabus', NULL, NULL, '[]', 24576, ?2, ?2, 0)",
            rusqlite::params![Uuid::new_v4().to_string(), now_s],
        )?;

        let profile_id = Uuid::new_v4().to_string();
        conn.execute(
            "INSERT INTO profile
             (id, full_name, email, phone, university_name, major, graduation_year, created_at, updated_at)
             VALUES (?1, 'Alex Student', 'alex@college.edu', '', 'State University', 'Computer Science', ?2, ?3, ?3)",
            rusqlite::params![profile_id, year + 2, now_s],
        )?;
        conn.execute(
            "INSERT INTO experience
             (id, profile_id, title, organization, start_date, end_date, summary, sort_order)
             VALUES (?1, ?2, 'Research Assistant', 'State University Lab', '2025-06-01', NULL, 'Assisted with ML data labeling and weekly lab reports.', 0)",
            rusqlite::params![Uuid::new_v4().to_string(), profile_id],
        )?;
        conn.execute(
            "INSERT INTO experience
             (id, profile_id, title, organization, start_date, end_date, summary, sort_order)
             VALUES (?1, ?2, 'Barista', 'Campus Cafe', '2024-09-01', '2025-05-15', 'Customer service and opening shifts.', 1)",
            rusqlite::params![Uuid::new_v4().to_string(), profile_id],
        )?;
        conn.execute(
            "INSERT INTO achievement (id, profile_id, title, issuer, date_received, notes)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
            rusqlite::params![
                Uuid::new_v4().to_string(),
                profile_id,
                "Dean's List",
                "State University",
                "2025-12-15",
                "Fall term GPA recognition."
            ],
        )?;
        for (name, category, amount) in [
            ("Groceries", "Food", 350.0),
            ("Transit", "Transport", 80.0),
            ("Textbooks", "School", 120.0),
        ] {
            conn.execute(
                "INSERT INTO finance_budget (id, name, category, amount, period)
                 VALUES (?1, ?2, ?3, ?4, 'monthly')",
                rusqlite::params![Uuid::new_v4().to_string(), name, category, amount],
            )?;
        }

        let uni_id = "seed-stateu".to_string();
        conn.execute(
            "INSERT OR IGNORE INTO university (id, name, short_name, domain, catalog_base_url, is_active)
             VALUES (?1, 'State University', 'StateU', 'stateu.edu', 'https://catalog.stateu.edu', 1)",
            rusqlite::params![uni_id],
        )?;
        conn.execute(
            "DELETE FROM course_catalog WHERE university_id = ?1",
            rusqlite::params![uni_id],
        )?;
        for (code, title, credits, description) in [
            (
                "CS 101",
                "Intro to Computer Science",
                3.0,
                "Programming foundations, algorithms, and problem solving.",
            ),
            (
                "CS 201",
                "Data Structures",
                4.0,
                "Lists, trees, graphs, and asymptotic analysis.",
            ),
            (
                "MATH 201",
                "Calculus II",
                4.0,
                "Integration techniques and series.",
            ),
            (
                "ENG 110",
                "College Writing",
                3.0,
                "Academic writing and research methods.",
            ),
            (
                "PHYS 120",
                "Physics I",
                4.0,
                "Mechanics and introductory lab.",
            ),
        ] {
            conn.execute(
                "INSERT INTO course_catalog
                 (id, university_id, department_id, code, title, credits, description, prerequisites, is_archived, stable_id)
                 VALUES (?1, ?2, NULL, ?3, ?4, ?5, ?6, '', 0, ?3)",
                rusqlite::params![
                    Uuid::new_v4().to_string(),
                    uni_id,
                    code,
                    title,
                    credits,
                    description
                ],
            )?;
        }
        let major_id = "seed-cs-bs".to_string();
        conn.execute(
            "INSERT OR IGNORE INTO major (id, university_id, name, degree_type, program_url, stable_id)
             VALUES (?1, ?2, 'Computer Science', 'BS', '', 'cs-bs')",
            rusqlite::params![major_id, uni_id],
        )?;
        // Refresh sample requirements for the seed major.
        conn.execute(
            "DELETE FROM catalog_degree_requirement WHERE major_id = ?1",
            rusqlite::params![major_id],
        )?;
        for (section, rule, credits, order) in [
            (
                "Core CS",
                r#"{"allOf":["CS 101"]}"#,
                Some(3.0),
                0i64,
            ),
            (
                "Mathematics",
                r#"{"allOf":["MATH 201"]}"#,
                Some(4.0),
                1,
            ),
            (
                "Writing",
                r#"{"anyOf":["ENG 110"]}"#,
                Some(3.0),
                2,
            ),
            (
                "Electives",
                r#"{}"#,
                Some(6.0),
                3,
            ),
        ] {
            conn.execute(
                "INSERT INTO catalog_degree_requirement
                 (id, university_id, major_id, section_title, rule_json, credits_required, sort_order)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
                rusqlite::params![
                    Uuid::new_v4().to_string(),
                    uni_id,
                    major_id,
                    section,
                    rule,
                    credits,
                    order
                ],
            )?;
        }

        let math_minor_id = "seed-math-minor".to_string();
        conn.execute(
            "INSERT OR IGNORE INTO major (id, university_id, name, degree_type, program_url, stable_id)
             VALUES (?1, ?2, 'Mathematics', 'Minor', '', 'math-minor')",
            rusqlite::params![math_minor_id, uni_id],
        )?;
        conn.execute(
            "DELETE FROM catalog_degree_requirement WHERE major_id = ?1",
            rusqlite::params![math_minor_id],
        )?;
        for (section, rule, credits, order) in [
            (
                "Calculus sequence",
                r#"{"allOf":["MATH 201"]}"#,
                Some(4.0),
                0i64,
            ),
            (
                "Linear algebra",
                r#"{"anyOf":["MATH 220"]}"#,
                Some(3.0),
                1,
            ),
            (
                "Upper division electives",
                r#"{"anyOf":["MATH 301","MATH 310"]}"#,
                Some(6.0),
                2,
            ),
        ] {
            conn.execute(
                "INSERT INTO catalog_degree_requirement
                 (id, university_id, major_id, section_title, rule_json, credits_required, sort_order)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
                rusqlite::params![
                    Uuid::new_v4().to_string(),
                    uni_id,
                    math_minor_id,
                    section,
                    rule,
                    credits,
                    order
                ],
            )?;
        }
        conn.execute(
            "INSERT OR IGNORE INTO app_settings (key, value, updated_at) VALUES (?1, ?2, ?3)",
            rusqlite::params![
                crate::commands::academics::ACTIVE_PROGRAM_SETTING_KEY,
                major_id,
                Utc::now().to_rfc3339()
            ],
        )?;

        for (source_school, source_code, target_code, credits) in [
            ("Community College", "CSC 110", "CS 101", 3.0),
            ("Community College", "MAT 210", "MATH 201", 4.0),
            ("Coastal Tech", "WRIT 100", "ENG 110", 3.0),
        ] {
            let dedupe = format!(
                "{}|{}|{}",
                source_school.to_ascii_lowercase(),
                source_code.to_ascii_uppercase(),
                target_code.to_ascii_uppercase()
            );
            conn.execute(
                "INSERT OR IGNORE INTO transfer_equivalency
                 (id, source_school, source_code, target_code, credits, notes, dedupe_key, proof_document_id)
                 VALUES (?1, ?2, ?3, ?4, ?5, '', ?6, NULL)",
                rusqlite::params![
                    Uuid::new_v4().to_string(),
                    source_school,
                    source_code,
                    target_code,
                    credits,
                    dedupe
                ],
            )?;
        }

        for (name, city, st, website, unit) in [
            (
                "State University",
                "Springfield",
                "IL",
                "https://www.stateu.edu",
                "100001",
            ),
            (
                "Coastal Tech",
                "San Diego",
                "CA",
                "https://www.coastaltech.edu",
                "100002",
            ),
            (
                "Northbridge College",
                "Boston",
                "MA",
                "https://www.northbridge.edu",
                "100003",
            ),
            (
                "Prairie Liberal Arts",
                "Iowa City",
                "IA",
                "https://www.prairiela.edu",
                "100004",
            ),
        ] {
            conn.execute(
                "INSERT INTO discovery_institution_identity
                 (id, name, unit_id, state, city, website)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
                rusqlite::params![Uuid::new_v4().to_string(), name, unit, st, city, website],
            )?;
        }
        crate::commands::discovery::seed_demo_cds(conn)?;

        let portal_now = Utc::now().to_rfc3339();
        for (idx, (name, url, notes)) in [
            (
                "Canvas",
                "https://canvas.instructure.com",
                "Primary course LMS — sign in with school SSO.",
            ),
            (
                "Student Portal",
                "https://my.stateu.edu",
                "Registration, billing, and unofficial transcript.",
            ),
        ]
        .into_iter()
        .enumerate()
        {
            conn.execute(
                "INSERT INTO lms_portal (id, name, url, notes, sort_order, created_at, updated_at)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?6)",
                rusqlite::params![
                    Uuid::new_v4().to_string(),
                    name,
                    url,
                    notes,
                    idx as i64,
                    portal_now
                ],
            )?;
        }

        for (org, role, start, summary) in [
            (
                "Campus Research Lab",
                "Undergraduate Researcher",
                "2024-09-01",
                "Built data pipelines for course outcomes.",
            ),
            (
                "Local Nonprofit",
                "Volunteer Coordinator",
                "2023-06-01",
                "Scheduled tutors and tracked hours.",
            ),
        ] {
            conn.execute(
                "INSERT INTO career_path_entry
                 (id, profile_id, organization, role_title, start_date, end_date, summary, sort_order)
                 VALUES (?1, NULL, ?2, ?3, ?4, NULL, ?5, 0)",
                rusqlite::params![Uuid::new_v4().to_string(), org, role, start, summary],
            )?;
        }

        Ok(())
    })?;

    for domain in [
        "planner",
        "calendar",
        "career",
        "finance",
        "vault",
        "profile",
        "catalog",
        "discovery",
        "transfer",
        "lms",
    ] {
        bump(&app, &state, domain)?;
    }
    Ok(())
}
