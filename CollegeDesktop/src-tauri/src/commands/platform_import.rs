//! Read-only import from the native Swift College GRDB workspace (macOS).
//! Both apps stay intact — Swift DB is never modified.

use crate::commands::backup::backup_college_db;
use crate::commands::CmdResult;
use crate::db::DbChangeEvent;
use crate::paths::{swift_document_vault_path, AppPaths};
use crate::swift_mirror::{
    import_finance_accounts_swift, import_finance_transactions_swift, import_zprofile,
    mirror_all_tables,
};
use crate::AppState;
use crate::db::AppDb;
use anyhow::{Context, Result};
use chrono::Utc;
use rusqlite::Connection;
use serde::{Deserialize, Serialize};
use std::collections::HashSet;
use std::fs;
use std::path::{Path, PathBuf};
use tauri::{AppHandle, Emitter, State};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum SourceSchema {
    SwiftGrdb,
    TauriNative,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ImportSwiftWorkspaceInput {
    pub swift_college_db: Option<String>,
    pub swift_finance_db: Option<String>,
    pub domains: Option<Vec<String>>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ImportSwiftWorkspaceReport {
    pub swift_db_path: String,
    pub source_schema: String,
    pub profile_rows: i64,
    pub experience_rows: i64,
    pub achievement_rows: i64,
    pub semester_rows: i64,
    pub course_rows: i64,
    pub task_rows: i64,
    pub calendar_rows: i64,
    pub application_rows: i64,
    pub posting_rows: i64,
    pub settings_rows: i64,
    pub vault_rows: i64,
    pub vault_files_copied: i64,
    pub finance_rows: i64,
    pub mirrored_tables: i64,
    pub mirrored_rows: i64,
    pub zprofile_rows: i64,
    pub total_rows: i64,
    pub skipped_reason: Option<String>,
}

const TAURI_MIRROR_TABLES: &[&str] = &[
    "app_settings",
    "planner_plan",
    "academic_profile",
    "graduation_plan_term",
    "recruiter_contact",
    "workday_job_posting",
    "career_event",
    "career_path_entry",
    "focus_block",
    "job_board_company",
    "lms_portal",
    "calendar_source",
    "watched_folder",
    "finance_account",
    "finance_transaction",
    "finance_budget",
    "finance_recurring",
    "finance_goal",
    "finance_inventory_item",
    "finance_receipt",
    "finance_holding",
];

fn default_swift_college_db() -> Option<PathBuf> {
    crate::paths::swift_college_db_path()
}

fn default_swift_finance_db() -> Option<PathBuf> {
    crate::paths::swift_finance_db_path()
}

fn canonical_path(path: &Path) -> PathBuf {
    path.canonicalize().unwrap_or_else(|_| path.to_path_buf())
}

fn copy_to_temp(src: &Path, label: &str) -> Result<PathBuf> {
    let tmp = std::env::temp_dir().join(format!(
        "college-{label}-import-{}.sqlite",
        uuid::Uuid::new_v4()
    ));
    fs::copy(src, &tmp).with_context(|| format!("copy Swift DB from {}", src.display()))?;
    Ok(tmp)
}

fn swift_table_exists(conn: &Connection, swift: &str, table: &str) -> rusqlite::Result<i64> {
    let sql = format!(
        "SELECT COUNT(1) FROM {swift}.sqlite_master WHERE type = 'table' AND name = ?1"
    );
    conn.query_row(&sql, rusqlite::params![table], |r| r.get(0))
}

fn swift_column_exists(
    conn: &Connection,
    swift: &str,
    table: &str,
    column: &str,
) -> rusqlite::Result<bool> {
    if swift_table_exists(conn, swift, table)? == 0 {
        return Ok(false);
    }
    let sql = format!("PRAGMA {swift}.table_info({table})");
    let mut stmt = conn.prepare(&sql)?;
    let mut rows = stmt.query([])?;
    while let Some(row) = rows.next()? {
        let name: String = row.get(1)?;
        if name == column {
            return Ok(true);
        }
    }
    Ok(false)
}

fn detect_source_schema(conn: &Connection, swift: &str) -> SourceSchema {
    let has_swift_name = swift_column_exists(conn, swift, "profile", "name").unwrap_or(false);
    let has_tauri_name = swift_column_exists(conn, swift, "profile", "full_name").unwrap_or(false);
    if has_swift_name && !has_tauri_name {
        SourceSchema::SwiftGrdb
    } else {
        SourceSchema::TauriNative
    }
}

fn table_columns(conn: &Connection, schema: &str, table: &str) -> rusqlite::Result<Vec<String>> {
    let sql = if schema.is_empty() {
        format!("PRAGMA table_info({table})")
    } else {
        format!("PRAGMA {schema}.table_info({table})")
    };
    let mut stmt = conn.prepare(&sql)?;
    let mut rows = stmt.query([])?;
    let mut cols = Vec::new();
    while let Some(row) = rows.next()? {
        cols.push(row.get(1)?);
    }
    Ok(cols)
}

fn copy_table_intersection(conn: &Connection, swift: &str, table: &str) -> rusqlite::Result<i64> {
    if swift_table_exists(conn, swift, table)? == 0 {
        return Ok(0);
    }
    let dest_cols = table_columns(conn, "", table)?;
    let src_cols = table_columns(conn, swift, table)?;
    if dest_cols.is_empty() || src_cols.is_empty() {
        return Ok(0);
    }
    let src_set: HashSet<_> = src_cols.iter().collect();
    let common: Vec<String> = dest_cols
        .into_iter()
        .filter(|c| src_set.contains(c))
        .collect();
    if common.is_empty() {
        return Ok(0);
    }
    let cols = common.join(", ");
    let sql = format!(
        "INSERT OR IGNORE INTO {table} ({cols}) SELECT {cols} FROM {swift}.{table}"
    );
    conn.execute(&sql, [])?;
    Ok(conn.changes() as i64)
}

fn domain_enabled(domains: Option<&[String]>, key: &str) -> bool {
    match domains {
        None => true,
        Some(list) if list.is_empty() => true,
        Some(list) => list.iter().any(|d| d == key || d == "all"),
    }
}

fn import_profile_swift(conn: &Connection, swift: &str, now: &str) -> rusqlite::Result<i64> {
    if swift_table_exists(conn, swift, "profile")? == 0 {
        return Ok(0);
    }
    conn.execute(
        &format!(
            "INSERT OR REPLACE INTO profile
             (id, full_name, email, phone, university_name, major, graduation_year, created_at, updated_at)
             SELECT id,
                    COALESCE(name, ''),
                    COALESCE(universityEmail, ''),
                    COALESCE(personalPhone, ''),
                    COALESCE(collegeName, ''),
                    '',
                    NULL,
                    ?1, ?1
             FROM {swift}.profile"
        ),
        rusqlite::params![now],
    )?;
    Ok(conn.changes() as i64)
}

fn import_profile_tauri(conn: &Connection, swift: &str) -> rusqlite::Result<i64> {
    copy_table_intersection(conn, swift, "profile")
}

fn import_experience_swift(conn: &Connection, swift: &str) -> rusqlite::Result<i64> {
    if swift_table_exists(conn, swift, "experience")? == 0 {
        return Ok(0);
    }
    conn.execute(
        &format!(
            "INSERT OR IGNORE INTO experience
             (id, profile_id, title, organization, start_date, end_date, summary, sort_order)
             SELECT e.id,
                    COALESCE(e.profileID, (SELECT id FROM profile LIMIT 1)),
                    COALESCE(e.title, ''),
                    COALESCE(e.company, ''),
                    CASE WHEN e.startDate IS NOT NULL AND e.startDate > 0
                         THEN datetime(e.startDate, 'unixepoch') ELSE NULL END,
                    CASE WHEN e.endDate IS NOT NULL AND e.endDate > 0
                         THEN datetime(e.endDate, 'unixepoch') ELSE NULL END,
                    COALESCE(e.descriptionText, ''),
                    0
             FROM {swift}.experience e"
        ),
        [],
    )?;
    Ok(conn.changes() as i64)
}

fn import_achievement_swift(conn: &Connection, swift: &str) -> rusqlite::Result<i64> {
    if swift_table_exists(conn, swift, "achievement")? == 0 {
        return Ok(0);
    }
    conn.execute(
        &format!(
            "INSERT OR IGNORE INTO achievement
             (id, profile_id, title, issuer, notes, sort_order)
             SELECT a.id,
                    COALESCE(a.profileID, (SELECT id FROM profile LIMIT 1)),
                    COALESCE(a.name, ''),
                    COALESCE(a.organization, ''),
                    COALESCE(a.descriptionText, ''),
                    0
             FROM {swift}.achievement a"
        ),
        [],
    )?;
    Ok(conn.changes() as i64)
}

fn import_semesters_swift(conn: &Connection, swift: &str) -> rusqlite::Result<i64> {
    if swift_table_exists(conn, swift, "planner_semester")? == 0 {
        return Ok(0);
    }
    conn.execute(
        &format!(
            "INSERT OR IGNORE INTO planner_semester
             (id, plan_id, year, season, label, is_current, sort_order)
             SELECT s.id,
                    s.planID,
                    COALESCE(s.year, 0),
                    COALESCE(s.season, 'Fall'),
                    COALESCE(s.name, ''),
                    0,
                    COALESCE(s.seasonOrder, 0)
             FROM {swift}.planner_semester s"
        ),
        [],
    )?;
    Ok(conn.changes() as i64)
}

fn import_courses_swift(conn: &Connection, swift: &str) -> rusqlite::Result<i64> {
    if swift_table_exists(conn, swift, "planner_course")? == 0 {
        return Ok(0);
    }
    conn.execute(
        &format!(
            "INSERT OR IGNORE INTO planner_course
             (id, semester_id, catalog_course_id, code, title, credits, grade, status, sort_order)
             SELECT c.id,
                    COALESCE(c.semesterID, (SELECT id FROM planner_semester LIMIT 1)),
                    c.catalogCourseID,
                    COALESCE(c.code, ''),
                    COALESCE(c.name, ''),
                    CAST(COALESCE(c.credits, 0) AS REAL),
                    c.grade,
                    COALESCE(c.status, CASE WHEN c.isCompleted = 1 THEN 'completed' ELSE 'planned' END),
                    COALESCE(c.sortOrder, 0)
             FROM {swift}.planner_course c"
        ),
        [],
    )?;
    Ok(conn.changes() as i64)
}

fn import_tasks_swift(conn: &Connection, swift: &str) -> rusqlite::Result<i64> {
    if swift_table_exists(conn, swift, "planner_task")? == 0 {
        return Ok(0);
    }
    conn.execute(
        &format!(
            "INSERT OR IGNORE INTO planner_task
             (id, semester_id, course_id, title, due_at, is_complete, notes, lms_item_id)
             SELECT t.id,
                    t.semesterID,
                    t.courseID,
                    COALESCE(t.title, 'Task'),
                    CASE WHEN t.dueDate IS NOT NULL AND t.dueDate > 0
                         THEN datetime(t.dueDate, 'unixepoch') ELSE NULL END,
                    CASE WHEN t.isComplete = 1 THEN 1 ELSE 0 END,
                    COALESCE(t.notes, ''),
                    t.lmsItemId
             FROM {swift}.planner_task t"
        ),
        [],
    )?;
    Ok(conn.changes() as i64)
}

fn import_calendar_swift(conn: &Connection, swift: &str, now: &str) -> rusqlite::Result<i64> {
    if swift_table_exists(conn, swift, "calendar_event")? == 0 {
        return Ok(0);
    }
    conn.execute(
        &format!(
            "INSERT OR IGNORE INTO calendar_event
             (id, title, start_at, end_at, all_day, location, notes, provider, provider_event_id,
              semester_id, course_id, color_hex, created_at, updated_at)
             SELECT e.id,
                    COALESCE(e.title, 'Event'),
                    datetime(e.startDate, 'unixepoch'),
                    datetime(e.endDate, 'unixepoch'),
                    CASE WHEN e.allDay = 1 THEN 1 ELSE 0 END,
                    COALESCE(e.location, ''),
                    COALESCE(e.notes, ''),
                    COALESCE(e.providerSource, 'swift_import'),
                    e.providerEventId,
                    e.semesterID,
                    e.courseID,
                    e.customColorHex,
                    ?1, ?1
             FROM {swift}.calendar_event e
             WHERE e.startDate IS NOT NULL AND e.startDate > 0"
        ),
        rusqlite::params![now],
    )?;
    Ok(conn.changes() as i64)
}

fn import_applications_swift(conn: &Connection, swift: &str, now: &str) -> rusqlite::Result<i64> {
    if swift_table_exists(conn, swift, "job_application")? == 0 {
        return Ok(0);
    }
    conn.execute(
        &format!(
            "INSERT OR IGNORE INTO job_application
             (id, company, role_title, status, location, url, applied_at, notes, salary_text,
              sort_order, created_at, updated_at)
             SELECT j.id,
                    COALESCE(j.company, ''),
                    COALESCE(j.title, ''),
                    COALESCE(j.statusRaw, 'interested'),
                    COALESCE(j.locationText, ''),
                    COALESCE(j.postingURLString, ''),
                    CASE WHEN j.dateApplied IS NOT NULL AND j.dateApplied > 0
                         THEN datetime(j.dateApplied, 'unixepoch') ELSE NULL END,
                    COALESCE(j.jobDescriptionText, ''),
                    COALESCE(j.baseSalaryText, ''),
                    COALESCE(j.sortOrder, 0),
                    ?1, ?1
             FROM {swift}.job_application j"
        ),
        rusqlite::params![now],
    )?;
    Ok(conn.changes() as i64)
}

fn import_postings_swift(conn: &Connection, swift: &str) -> rusqlite::Result<i64> {
    if swift_table_exists(conn, swift, "workday_job_posting")? == 0 {
        return Ok(0);
    }
    if swift_column_exists(conn, swift, "workday_job_posting", "title")? {
        return copy_table_intersection(conn, swift, "workday_job_posting");
    }
    conn.execute(
        &format!(
            "INSERT OR IGNORE INTO workday_job_posting
             (id, company, title, location, url, posted_at, tracked_application_id, raw_json)
             SELECT p.id,
                    COALESCE(p.companyName, ''),
                    COALESCE(p.jobTitle, ''),
                    COALESCE(p.locationText, ''),
                    COALESCE(p.postingURLString, ''),
                    CASE WHEN p.postedAt IS NOT NULL AND p.postedAt > 0
                         THEN datetime(p.postedAt, 'unixepoch') ELSE NULL END,
                    p.trackedApplicationID,
                    COALESCE(p.rawPayloadJSON, '{{}}')
             FROM {swift}.workday_job_posting p"
        ),
        [],
    )?;
    Ok(conn.changes() as i64)
}

fn import_settings_swift(conn: &Connection, swift: &str, now: &str) -> rusqlite::Result<i64> {
    if swift_table_exists(conn, swift, "app_settings")? == 0 {
        return Ok(0);
    }
    if swift_column_exists(conn, swift, "app_settings", "updated_at")? {
        return copy_table_intersection(conn, swift, "app_settings");
    }
    conn.execute(
        &format!(
            "INSERT OR REPLACE INTO app_settings (key, value, updated_at)
             SELECT key, value, ?1 FROM {swift}.app_settings"
        ),
        rusqlite::params![now],
    )?;
    Ok(conn.changes() as i64)
}

fn import_vault_swift(conn: &Connection, swift: &str) -> rusqlite::Result<i64> {
    if swift_table_exists(conn, swift, "vault_document")? == 0 {
        return Ok(0);
    }
    if swift_column_exists(conn, swift, "vault_document", "relative_path")? {
        return copy_table_intersection(conn, swift, "vault_document");
    }
    conn.execute(
        &format!(
            "INSERT OR IGNORE INTO vault_document
             (id, title, relative_path, mime_type, category, parent_folder_id, course_id,
              tags_json, file_size, created_at, updated_at, sort_order)
             SELECT d.id,
                    COALESCE(d.customDisplayName, d.fileName, ''),
                    COALESCE(d.localRelativePath, ''),
                    '',
                    COALESCE(d.category, 'general'),
                    d.parentFolderID,
                    d.courseCodeLinked,
                    COALESCE(d.tags, '[]'),
                    COALESCE(d.fileSizeBytes, 0),
                    datetime(d.addedAt, 'unixepoch'),
                    datetime(COALESCE(d.lastOpenedAt, d.addedAt), 'unixepoch'),
                    COALESCE(d.sortOrder, 0)
             FROM {swift}.vault_document d
             WHERE COALESCE(d.isFolder, 0) = 0"
        ),
        [],
    )?;
    Ok(conn.changes() as i64)
}

fn import_finance_tables(conn: &Connection, finance: &str) -> rusqlite::Result<i64> {
    let mut total = 0i64;
    for table in [
        "finance_account",
        "finance_transaction",
        "finance_budget",
        "finance_recurring",
        "finance_goal",
        "finance_inventory_item",
        "finance_receipt",
        "finance_holding",
    ] {
        total += copy_table_intersection(conn, finance, table).unwrap_or(0);
    }
    Ok(total)
}

fn copy_swift_vault_files(paths: &AppPaths) -> Result<i64> {
    let src = match swift_document_vault_path() {
        Some(p) if p.is_dir() => p,
        _ => return Ok(0),
    };
    fs::create_dir_all(&paths.vault_dir)?;
    copy_vault_tree(&src, &paths.vault_dir)
}

fn copy_vault_tree(src: &Path, dest: &Path) -> Result<i64> {
    let mut copied = 0i64;
    for entry in fs::read_dir(src)? {
        let entry = entry?;
        let from = entry.path();
        let to = dest.join(entry.file_name());
        if from.is_file() {
            if !to.exists() {
                fs::copy(&from, &to)?;
                copied += 1;
            }
        } else if from.is_dir() {
            fs::create_dir_all(&to)?;
            copied += copy_vault_tree(&from, &to)?;
        }
    }
    Ok(copied)
}

pub fn import_swift_workspace_inner(
    db: &AppDb,
    paths: &AppPaths,
    input: ImportSwiftWorkspaceInput,
) -> Result<ImportSwiftWorkspaceReport> {
    let src = input
        .swift_college_db
        .filter(|s| !s.trim().is_empty())
        .map(PathBuf::from)
        .or_else(default_swift_college_db)
        .context("Could not resolve Swift College.sqlite path")?;

    if !src.exists() {
        anyhow::bail!("Swift database not found at {}", src.display());
    }

    let finance_src = input
        .swift_finance_db
        .filter(|s| !s.trim().is_empty())
        .map(PathBuf::from)
        .or_else(default_swift_finance_db)
        .filter(|p| p.exists());

    let same_as_live = canonical_path(&src) == canonical_path(&paths.college_db_path);

    let _backup = backup_college_db(
        db,
        &paths.college_db_path,
        &paths.vault_dir,
        &paths.backups_dir,
    )?;
    let temp = copy_to_temp(&src, "swift")?;
    let attach_uri = format!(
        "file:{}?mode=ro",
        temp.display().to_string().replace('\\', "/").replace('\'', "''")
    );
    let now = Utc::now().to_rfc3339();
    let domains = input.domains.as_deref();

    let mut finance_temp: Option<PathBuf> = None;
    let finance_attach = if let Some(finance_src) = finance_src {
        let tmp = copy_to_temp(&finance_src, "swift-finance")?;
        let path = format!(
            "file:{}?mode=ro",
            tmp.display().to_string().replace('\\', "/").replace('\'', "''")
        );
        finance_temp = Some(tmp);
        Some(path)
    } else {
        None
    };

    let report = db.with_conn(|conn| {
        conn.execute_batch("PRAGMA foreign_keys = OFF;")?;
        conn.execute(
            &format!("ATTACH DATABASE '{attach_uri}' AS swift"),
            [],
        )?;
        if let Some(ref finance_path) = finance_attach {
            conn.execute(
                &format!("ATTACH DATABASE '{finance_path}' AS swift_finance"),
                [],
            )?;
        }

        let schema = detect_source_schema(conn, "swift");
        let schema_label = match schema {
            SourceSchema::SwiftGrdb => "swift_grdb",
            SourceSchema::TauriNative => "tauri_native",
        };

        let mut profile_rows = 0i64;
        let mut experience_rows = 0i64;
        let mut achievement_rows = 0i64;
        let mut semester_rows = 0i64;
        let mut course_rows = 0i64;
        let mut task_rows = 0i64;
        let mut calendar_rows = 0i64;
        let mut application_rows = 0i64;
        let mut posting_rows = 0i64;
        let mut settings_rows = 0i64;
        let mut vault_rows = 0i64;
        let mut finance_rows = 0i64;
        let mut mirrored_tables = 0i64;
        let mut mirrored_rows = 0i64;
        let zprofile_rows = import_zprofile(conn, "swift", &now).unwrap_or(0);

        if domain_enabled(domains, "profile") {
            profile_rows = match schema {
                SourceSchema::SwiftGrdb => import_profile_swift(conn, "swift", &now).unwrap_or(0),
                SourceSchema::TauriNative => import_profile_tauri(conn, "swift").unwrap_or(0),
            };
            experience_rows = match schema {
                SourceSchema::SwiftGrdb => import_experience_swift(conn, "swift").unwrap_or(0),
                SourceSchema::TauriNative => {
                    copy_table_intersection(conn, "swift", "experience").unwrap_or(0)
                }
            };
            achievement_rows = match schema {
                SourceSchema::SwiftGrdb => import_achievement_swift(conn, "swift").unwrap_or(0),
                SourceSchema::TauriNative => {
                    copy_table_intersection(conn, "swift", "achievement").unwrap_or(0)
                }
            };
        }

        if domain_enabled(domains, "planner") {
            semester_rows = match schema {
                SourceSchema::SwiftGrdb => import_semesters_swift(conn, "swift").unwrap_or(0),
                SourceSchema::TauriNative => {
                    copy_table_intersection(conn, "swift", "planner_semester").unwrap_or(0)
                }
            };
            course_rows = match schema {
                SourceSchema::SwiftGrdb => import_courses_swift(conn, "swift").unwrap_or(0),
                SourceSchema::TauriNative => {
                    copy_table_intersection(conn, "swift", "planner_course").unwrap_or(0)
                }
            };
            task_rows = match schema {
                SourceSchema::SwiftGrdb => import_tasks_swift(conn, "swift").unwrap_or(0),
                SourceSchema::TauriNative => {
                    copy_table_intersection(conn, "swift", "planner_task").unwrap_or(0)
                }
            };
        }

        if domain_enabled(domains, "calendar") {
            calendar_rows = match schema {
                SourceSchema::SwiftGrdb => import_calendar_swift(conn, "swift", &now).unwrap_or(0),
                SourceSchema::TauriNative => {
                    copy_table_intersection(conn, "swift", "calendar_event").unwrap_or(0)
                }
            };
        }

        if domain_enabled(domains, "career") {
            application_rows = match schema {
                SourceSchema::SwiftGrdb => {
                    import_applications_swift(conn, "swift", &now).unwrap_or(0)
                }
                SourceSchema::TauriNative => {
                    copy_table_intersection(conn, "swift", "job_application").unwrap_or(0)
                }
            };
            posting_rows = import_postings_swift(conn, "swift").unwrap_or(0);
        }

        if domain_enabled(domains, "settings") {
            settings_rows = import_settings_swift(conn, "swift", &now).unwrap_or(0);
        }

        if domain_enabled(domains, "vault") {
            vault_rows = import_vault_swift(conn, "swift").unwrap_or(0);
        }

        if domain_enabled(domains, "finance") {
            if finance_attach.is_some() {
                finance_rows += import_finance_accounts_swift(conn, "swift_finance").unwrap_or(0);
                finance_rows +=
                    import_finance_transactions_swift(conn, "swift_finance").unwrap_or(0);
                finance_rows += import_finance_tables(conn, "swift_finance").unwrap_or(0);
                let fin_mirror = mirror_all_tables(conn, "swift_finance").unwrap_or_default();
                finance_rows += fin_mirror.rows;
                mirrored_tables += fin_mirror.tables;
                mirrored_rows += fin_mirror.rows;
            }
        }

        let college_mirror = mirror_all_tables(conn, "swift").unwrap_or_default();
        mirrored_tables += college_mirror.tables;
        mirrored_rows += college_mirror.rows;

        if schema == SourceSchema::TauriNative {
            for table in TAURI_MIRROR_TABLES {
                if table.starts_with("finance_") && finance_attach.is_none() {
                    continue;
                }
                if *table == "app_settings" && domain_enabled(domains, "settings") {
                    continue;
                }
                if *table == "workday_job_posting" && domain_enabled(domains, "career") {
                    continue;
                }
                let enabled = match *table {
                    "focus_block" | "planner_plan" | "academic_profile" | "graduation_plan_term" => {
                        domain_enabled(domains, "planner")
                    }
                    "lms_portal" => domain_enabled(domains, "lms"),
                    "calendar_source" => domain_enabled(domains, "calendar"),
                    t if t.starts_with("finance_") => domain_enabled(domains, "finance"),
                    t if t.starts_with("career_") || t == "recruiter_contact" || t == "job_board_company" => {
                        domain_enabled(domains, "career")
                    }
                    "watched_folder" => domain_enabled(domains, "vault"),
                    _ => true,
                };
                if enabled {
                    let _ = copy_table_intersection(conn, "swift", table);
                }
            }
        }

        let _ = conn.execute_batch("DETACH DATABASE swift;");
        if finance_attach.is_some() {
            let _ = conn.execute_batch("DETACH DATABASE swift_finance;");
        }
        conn.execute_batch("PRAGMA foreign_keys = ON;")?;

        let total_rows = profile_rows
            + experience_rows
            + achievement_rows
            + semester_rows
            + course_rows
            + task_rows
            + calendar_rows
            + application_rows
            + posting_rows
            + settings_rows
            + vault_rows
            + finance_rows
            + mirrored_rows
            + zprofile_rows;

        let skipped_reason = if same_as_live && total_rows == 0 {
            Some(
                "Source is the live Tauri database (same path on macOS). \
                 Export a backup from the Swift app (grdb-College.sqlite) and pick that file to import older Swift-only data."
                    .into(),
            )
        } else if same_as_live {
            Some(
                "Source path matches the live Tauri database — only new row IDs were merged."
                    .into(),
            )
        } else {
            None
        };

        Ok(ImportSwiftWorkspaceReport {
            swift_db_path: src.display().to_string(),
            source_schema: schema_label.into(),
            profile_rows,
            experience_rows,
            achievement_rows,
            semester_rows,
            course_rows,
            task_rows,
            calendar_rows,
            application_rows,
            posting_rows,
            settings_rows,
            vault_rows,
            vault_files_copied: 0,
            finance_rows,
            mirrored_tables,
            mirrored_rows,
            zprofile_rows,
            total_rows,
            skipped_reason,
        })
    })?;

    let _ = fs::remove_file(&temp);
    if let Some(tmp) = finance_temp {
        let _ = fs::remove_file(tmp);
    }

    if domain_enabled(domains, "vault") {
        let copied = copy_swift_vault_files(paths).unwrap_or(0);
        return Ok(ImportSwiftWorkspaceReport {
            vault_files_copied: copied,
            total_rows: report.total_rows,
            ..report
        });
    }

    // Always attempt vault file copy even when vault domain rows are empty.
    let copied = copy_swift_vault_files(paths).unwrap_or(0);
    Ok(ImportSwiftWorkspaceReport {
        vault_files_copied: copied,
        ..report
    })
}

#[tauri::command]
pub fn platform_import_swift_workspace(
    app: AppHandle,
    state: State<'_, AppState>,
    input: ImportSwiftWorkspaceInput,
) -> CmdResult<ImportSwiftWorkspaceReport> {
    let report = import_swift_workspace_inner(&state.db, &state.paths, input)?;

    for domain in [
        "profile",
        "planner",
        "calendar",
        "career",
        "settings",
        "vault",
        "finance",
    ] {
        if let Ok(rev) = state.db.bump_revision(domain) {
            let _ = app.emit(
                "db:change",
                DbChangeEvent {
                    domain: domain.into(),
                    revision: rev,
                },
            );
        }
    }

    Ok(report)
}

/// Re-import events from the published ICS feed (EventKit substitute round-trip).
#[tauri::command]
pub fn platform_sync_published_calendar_feed(
    app: AppHandle,
    state: State<'_, AppState>,
) -> CmdResult<crate::commands::calendar::SyncIcsResult> {
    use crate::commands::calendar;
    let feed = calendar::publish_subscribe_feed_inner(&state)?;
    let text = std::fs::read_to_string(&feed.path).map_err(anyhow::Error::from)?;
    let (imported, skipped) = state.db.with_conn(|conn| {
        calendar::import_ics_into_conn(conn, &text, None, "ics_feed", "").map_err(Into::into)
    })?;
    let rev = state.db.bump_revision("calendar")?;
    let _ = app.emit(
        "db:change",
        DbChangeEvent {
            domain: "calendar".into(),
            revision: rev,
        },
    );
    Ok(calendar::SyncIcsResult {
        imported,
        skipped,
        last_synced_at: feed.written_at,
    })
}
