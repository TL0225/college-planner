use crate::commands::assistant_tools_extended::extract_course_codes;
use crate::commands::CmdResult;
use crate::db::DbChangeEvent;
use crate::AppState;
use chrono::Utc;
use rusqlite::Connection;
use rusqlite::OptionalExtension;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::collections::HashMap;
use tauri::{AppHandle, Emitter, State};

pub const ACTIVE_PROGRAM_SETTING_KEY: &str = "academics.activeMajorId";

pub(crate) const FULFILLMENT_KEY_PREFIX: &str = "academics.fulfillment.";

pub(crate) fn fulfillment_setting_key(category_id: &str) -> String {
    format!("{FULFILLMENT_KEY_PREFIX}{category_id}")
}

pub(crate) fn load_fulfillment_map(conn: &Connection) -> rusqlite::Result<HashMap<String, Vec<String>>> {
    let mut stmt = conn.prepare(
        "SELECT key, value FROM app_settings WHERE key LIKE ?1",
    )?;
    let prefix = format!("{FULFILLMENT_KEY_PREFIX}%");
    let rows = stmt.query_map([prefix], |r| {
        Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?))
    })?;
    let mut map = HashMap::new();
    for row in rows {
        let (key, value) = row?;
        let Some(category_id) = key.strip_prefix(FULFILLMENT_KEY_PREFIX) else {
            continue;
        };
        let codes: Vec<String> = serde_json::from_str(&value).unwrap_or_default();
        if !codes.is_empty() {
            map.insert(category_id.to_string(), codes);
        }
    }
    Ok(map)
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AuditSummary {
    pub planned_credits: f64,
    pub completed_credits: f64,
    pub semester_count: i64,
    pub course_count: i64,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SemesterDto {
    pub id: String,
    pub year: i64,
    pub season: String,
    pub label: String,
    pub is_current: bool,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RequirementAuditItem {
    pub id: String,
    pub section_title: String,
    pub credits_required: Option<f64>,
    pub credits_earned: f64,
    pub status: String,
    pub matched_codes: Vec<String>,
    pub missing_codes: Vec<String>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RequirementAudit {
    pub items: Vec<RequirementAuditItem>,
    pub satisfied_count: i64,
    pub total_count: i64,
    pub progress_ratio: f64,
}

pub(crate) fn normalize_code(code: &str) -> String {
    code.chars()
        .filter(|c| !c.is_whitespace())
        .flat_map(|c| c.to_uppercase())
        .collect()
}

fn codes_from_rule(rule_json: &str) -> Vec<String> {
    let Ok(value) = serde_json::from_str::<Value>(rule_json) else {
        return Vec::new();
    };
    let mut codes = Vec::new();
    for key in ["codes", "anyOf", "allOf"] {
        if let Some(arr) = value.get(key).and_then(|v| v.as_array()) {
            for item in arr {
                if let Some(s) = item.as_str() {
                    codes.push(s.to_string());
                }
            }
        }
    }
    codes
}

#[tauri::command]
pub fn academics_get_audit_summary(state: State<'_, AppState>) -> CmdResult<AuditSummary> {
    state
        .db
        .with_conn(|conn| {
            let planned: f64 = conn
                .query_row(
                    "SELECT COALESCE(SUM(credits), 0) FROM planner_course WHERE status != 'dropped'",
                    [],
                    |r| r.get(0),
                )
                .unwrap_or(0.0);
            let completed: f64 = conn
                .query_row(
                    "SELECT COALESCE(SUM(credits), 0) FROM planner_course WHERE status = 'completed'",
                    [],
                    |r| r.get(0),
                )
                .unwrap_or(0.0);
            let semester_count: i64 = conn
                .query_row("SELECT COUNT(*) FROM planner_semester", [], |r| r.get(0))
                .unwrap_or(0);
            let course_count: i64 = conn
                .query_row("SELECT COUNT(*) FROM planner_course", [], |r| r.get(0))
                .unwrap_or(0);
            Ok(AuditSummary {
                planned_credits: planned,
                completed_credits: completed,
                semester_count,
                course_count,
            })
        })
        .map_err(Into::into)
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct GpaSummary {
    pub gpa: Option<f64>,
    pub graded_credits: f64,
    pub graded_courses: i64,
}

fn grade_points(grade: &str) -> Option<f64> {
    match grade.trim().to_ascii_uppercase().as_str() {
        "A+" | "A" => Some(4.0),
        "A-" => Some(3.7),
        "B+" => Some(3.3),
        "B" => Some(3.0),
        "B-" => Some(2.7),
        "C+" => Some(2.3),
        "C" => Some(2.0),
        "C-" => Some(1.7),
        "D+" => Some(1.3),
        "D" => Some(1.0),
        "D-" => Some(0.7),
        "F" => Some(0.0),
        _ => None,
    }
}

#[tauri::command]
pub fn academics_get_gpa_summary(state: State<'_, AppState>) -> CmdResult<GpaSummary> {
    state
        .db
        .with_conn(|conn| {
            let mut stmt = conn.prepare(
                "SELECT credits, grade FROM planner_course
                 WHERE status = 'completed' AND grade IS NOT NULL AND TRIM(grade) != ''",
            )?;
            let rows = stmt.query_map([], |r| {
                Ok((r.get::<_, f64>(0)?, r.get::<_, String>(1)?))
            })?;
            let mut points = 0.0f64;
            let mut credits = 0.0f64;
            let mut count = 0i64;
            for row in rows {
                let (cr, grade) = row?;
                if let Some(gp) = grade_points(&grade) {
                    points += gp * cr;
                    credits += cr;
                    count += 1;
                }
            }
            Ok(GpaSummary {
                gpa: if credits > 0.0 {
                    Some(points / credits)
                } else {
                    None
                },
                graded_credits: credits,
                graded_courses: count,
            })
        })
        .map_err(Into::into)
}

#[tauri::command]
pub fn academics_list_semesters(state: State<'_, AppState>) -> CmdResult<Vec<SemesterDto>> {
    state
        .db
        .with_conn(|conn| {
            let mut stmt = conn.prepare(
                "SELECT id, year, season, label, is_current FROM planner_semester
                 ORDER BY year DESC, sort_order ASC",
            )?;
            let rows = stmt
                .query_map([], |r| {
                    Ok(SemesterDto {
                        id: r.get(0)?,
                        year: r.get(1)?,
                        season: r.get(2)?,
                        label: r.get(3)?,
                        is_current: r.get::<_, i64>(4)? != 0,
                    })
                })?
                .collect::<Result<Vec<_>, _>>()?;
            Ok(rows)
        })
        .map_err(Into::into)
}

#[tauri::command]
pub fn academics_get_requirement_audit(state: State<'_, AppState>) -> CmdResult<RequirementAudit> {
    state
        .db
        .with_conn(|conn| {
            let mut course_stmt = conn.prepare(
                "SELECT code, credits, status FROM planner_course WHERE status != 'dropped'",
            )?;
            let planner: Vec<(String, f64, String)> = course_stmt
                .query_map([], |r| {
                    Ok((
                        r.get::<_, String>(0)?,
                        r.get::<_, f64>(1)?,
                        r.get::<_, String>(2)?,
                    ))
                })?
                .collect::<Result<Vec<_>, _>>()?;

            let mut by_code: std::collections::HashMap<String, (f64, String)> =
                std::collections::HashMap::new();
            for (code, credits, status) in &planner {
                by_code.insert(normalize_code(code), (*credits, status.clone()));
            }

            let active_major_id: Option<String> = conn
                .query_row(
                    "SELECT value FROM app_settings WHERE key = ?1",
                    rusqlite::params![ACTIVE_PROGRAM_SETTING_KEY],
                    |r| r.get(0),
                )
                .optional()?;

            let requirements: Vec<(String, String, String, Option<f64>)> =
                if let Some(major_id) = active_major_id.filter(|s| !s.is_empty()) {
                    let mut stmt = conn.prepare(
                        "SELECT id, section_title, rule_json, credits_required, sort_order
                         FROM catalog_degree_requirement
                         WHERE major_id = ?1
                         ORDER BY sort_order ASC, section_title ASC",
                    )?;
                    let rows = stmt.query_map(rusqlite::params![major_id], |r| {
                        Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?))
                    })?;
                    rows.collect::<Result<Vec<_>, _>>()?
                } else {
                    let mut stmt = conn.prepare(
                        "SELECT id, section_title, rule_json, credits_required, sort_order
                         FROM catalog_degree_requirement
                         ORDER BY sort_order ASC, section_title ASC",
                    )?;
                    let rows = stmt.query_map([], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?)))?;
                    rows.collect::<Result<Vec<_>, _>>()?
                };

            let fulfillment_map = load_fulfillment_map(conn)?;

            let mut items = Vec::new();
            let mut satisfied_count = 0i64;
            for (id, section_title, rule_json, credits_required) in requirements {
                let wanted = codes_from_rule(&rule_json);
                let manual = fulfillment_map.get(&id).cloned().unwrap_or_default();
                let mut matched = Vec::new();
                let mut missing = Vec::new();
                let mut credits_earned = 0.0;

                if wanted.is_empty() {
                    if manual.is_empty() {
                        credits_earned = by_code
                            .values()
                            .filter(|(_, status)| status == "completed")
                            .map(|(c, _)| *c)
                            .sum();
                    } else {
                        for code in &manual {
                            let key = normalize_code(code);
                            if let Some((credits, status)) = by_code.get(&key) {
                                matched.push(code.clone());
                                if status == "completed" {
                                    credits_earned += *credits;
                                }
                            } else {
                                matched.push(code.clone());
                            }
                        }
                    }
                } else {
                    for code in &wanted {
                        let key = normalize_code(code);
                        if let Some((credits, status)) = by_code.get(&key) {
                            matched.push(code.clone());
                            if status == "completed" {
                                credits_earned += *credits;
                            }
                        } else {
                            missing.push(code.clone());
                        }
                    }
                }

                for code in &manual {
                    let key = normalize_code(code);
                    if !matched.iter().any(|c| normalize_code(c) == key) {
                        matched.push(code.clone());
                    }
                    missing.retain(|c| normalize_code(c) != key);
                    if wanted.is_empty() || !wanted.iter().any(|c| normalize_code(c) == key) {
                        if let Some((credits, status)) = by_code.get(&key) {
                            if status == "completed" && !wanted.is_empty() {
                                credits_earned += *credits;
                            }
                        }
                    }
                }

                let status = if let Some(req) = credits_required {
                    if credits_earned + f64::EPSILON >= req {
                        "satisfied"
                    } else if !matched.is_empty() {
                        "in_progress"
                    } else {
                        "missing"
                    }
                } else if !wanted.is_empty() && missing.is_empty() {
                    let all_completed = matched.iter().all(|c| {
                        by_code
                            .get(&normalize_code(c))
                            .map(|(_, s)| s.as_str() == "completed")
                            .unwrap_or(false)
                    });
                    if all_completed {
                        "satisfied"
                    } else if !matched.is_empty() {
                        "in_progress"
                    } else {
                        "missing"
                    }
                } else if wanted.is_empty() {
                    "open"
                } else {
                    "missing"
                };

                if status == "satisfied" {
                    satisfied_count += 1;
                }

                items.push(RequirementAuditItem {
                    id,
                    section_title,
                    credits_required,
                    credits_earned,
                    status: status.to_string(),
                    matched_codes: matched,
                    missing_codes: missing,
                });
            }

            let total_count = items.len() as i64;
            let progress_ratio = if total_count == 0 {
                0.0
            } else {
                satisfied_count as f64 / total_count as f64
            };

            Ok(RequirementAudit {
                items,
                satisfied_count,
                total_count,
                progress_ratio,
            })
        })
        .map_err(Into::into)
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ProgramSummaryDto {
    pub id: String,
    pub name: String,
    pub degree_type: String,
    pub university_name: String,
    pub program_url: String,
    pub section_count: i64,
    pub is_active: bool,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ProgramRequirementDto {
    pub id: String,
    pub section_title: String,
    pub credits_required: Option<f64>,
    pub rule_codes: Vec<String>,
    pub sort_order: i64,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ProgramDetailDto {
    pub id: String,
    pub name: String,
    pub degree_type: String,
    pub university_name: String,
    pub program_url: String,
    pub is_active: bool,
    pub requirements: Vec<ProgramRequirementDto>,
}

fn read_active_program_id(conn: &Connection) -> rusqlite::Result<Option<String>> {
    conn.query_row(
        "SELECT value FROM app_settings WHERE key = ?1",
        rusqlite::params![ACTIVE_PROGRAM_SETTING_KEY],
        |r| r.get(0),
    )
    .optional()
}

#[tauri::command]
pub fn academics_list_programs(state: State<'_, AppState>) -> CmdResult<Vec<ProgramSummaryDto>> {
    state
        .db
        .with_conn(|conn| {
            let active = read_active_program_id(conn)?;
            let mut stmt = conn.prepare(
                "SELECT m.id, m.name, m.degree_type, m.program_url, u.name,
                        (SELECT COUNT(*) FROM catalog_degree_requirement r WHERE r.major_id = m.id)
                 FROM major m
                 JOIN university u ON u.id = m.university_id
                 ORDER BY m.degree_type ASC, m.name ASC
                 LIMIT 100",
            )?;
            let rows = stmt
                .query_map([], |r| {
                    Ok(ProgramSummaryDto {
                        id: r.get(0)?,
                        name: r.get(1)?,
                        degree_type: r.get(2)?,
                        program_url: r.get(3)?,
                        university_name: r.get(4)?,
                        section_count: r.get(5)?,
                        is_active: false,
                    })
                })?
                .collect::<Result<Vec<_>, _>>()?;
            Ok(rows
                .into_iter()
                .map(|mut row| {
                    row.is_active = active.as_deref() == Some(row.id.as_str());
                    row
                })
                .collect())
        })
        .map_err(Into::into)
}

#[tauri::command]
pub fn academics_get_program_detail(
    state: State<'_, AppState>,
    program_id: String,
) -> CmdResult<ProgramDetailDto> {
    state
        .db
        .with_conn(|conn| {
            let active = read_active_program_id(conn)?;
            let (id, name, degree_type, program_url, university_name): (
                String,
                String,
                String,
                String,
                String,
            ) = conn.query_row(
                "SELECT m.id, m.name, m.degree_type, m.program_url, u.name
                 FROM major m
                 JOIN university u ON u.id = m.university_id
                 WHERE m.id = ?1",
                rusqlite::params![program_id],
                |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?, r.get(4)?)),
            )?;
            let mut stmt = conn.prepare(
                "SELECT id, section_title, rule_json, credits_required, sort_order
                 FROM catalog_degree_requirement
                 WHERE major_id = ?1
                 ORDER BY sort_order ASC, section_title ASC",
            )?;
            let requirements = stmt
                .query_map(rusqlite::params![id], |r| {
                    let rule_json: String = r.get(2)?;
                    Ok(ProgramRequirementDto {
                        id: r.get(0)?,
                        section_title: r.get(1)?,
                        credits_required: r.get(3)?,
                        rule_codes: codes_from_rule(&rule_json),
                        sort_order: r.get(4)?,
                    })
                })?
                .collect::<Result<Vec<_>, _>>()?;
            Ok(ProgramDetailDto {
                id,
                name,
                degree_type,
                university_name,
                program_url,
                is_active: active.as_deref() == Some(program_id.as_str()),
                requirements,
            })
        })
        .map_err(Into::into)
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SetActiveProgramInput {
    pub program_id: String,
}

#[tauri::command]
pub fn academics_set_active_program(
    app: AppHandle,
    state: State<'_, AppState>,
    input: SetActiveProgramInput,
) -> CmdResult<()> {
    let now = Utc::now().to_rfc3339();
    state.db.with_conn(|conn| {
        let exists: i64 = conn.query_row(
            "SELECT COUNT(1) FROM major WHERE id = ?1",
            rusqlite::params![input.program_id],
            |r| r.get(0),
        )?;
        if exists == 0 {
            anyhow::bail!("Program not found");
        }
        conn.execute(
            "INSERT INTO app_settings (key, value, updated_at) VALUES (?1, ?2, ?3)
             ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at",
            rusqlite::params![ACTIVE_PROGRAM_SETTING_KEY, input.program_id, now],
        )?;
        Ok(())
    })?;
    let rev = state.db.bump_revision("planner")?;
    let _ = app.emit(
        "db:change",
        DbChangeEvent {
            domain: "planner".into(),
            revision: rev,
        },
    );
    Ok(())
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct GradingCategoryDto {
    pub id: String,
    pub course_id: String,
    pub name: String,
    pub weight: f64,
    pub sort_order: i64,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PrerequisiteEvaluation {
    pub satisfied: bool,
    pub missing_codes: Vec<String>,
    pub notes: String,
}

#[tauri::command]
pub fn academics_evaluate_prerequisites(
    state: State<'_, AppState>,
    course_code: String,
) -> CmdResult<PrerequisiteEvaluation> {
    let target = normalize_code(&course_code);
    if target.is_empty() {
        return Err(crate::commands::CommandError {
            message: "Course code is required".into(),
        });
    }

    state
        .db
        .with_conn(|conn| {
            let prereq_text: Option<String> = conn
                .query_row(
                    "SELECT prerequisites FROM course_catalog
                     WHERE REPLACE(UPPER(code), ' ', '') = ?1
                     LIMIT 1",
                    rusqlite::params![target],
                    |r| r.get(0),
                )
                .optional()?;

            let mut satisfied_codes: std::collections::HashSet<String> =
                std::collections::HashSet::new();
            let mut stmt = conn.prepare(
                "SELECT code FROM planner_course
                 WHERE status IN ('completed', 'in_progress')",
            )?;
            let rows = stmt.query_map([], |r| r.get::<_, String>(0))?;
            for row in rows {
                satisfied_codes.insert(normalize_code(&row?));
            }

            let Some(text) = prereq_text.filter(|s| !s.trim().is_empty()) else {
                return Ok(PrerequisiteEvaluation {
                    satisfied: true,
                    missing_codes: Vec::new(),
                    notes: format!("No prerequisite data on file for {course_code}."),
                });
            };

            let required: Vec<String> = extract_course_codes(&text)
                .into_iter()
                .map(|c| c.trim().to_string())
                .filter(|c| !c.is_empty())
                .collect();

            if required.is_empty() {
                return Ok(PrerequisiteEvaluation {
                    satisfied: true,
                    missing_codes: Vec::new(),
                    notes: format!(
                        "Prerequisite text for {course_code} could not be parsed into course codes: {text}"
                    ),
                });
            }

            let mut missing = Vec::new();
            for code in &required {
                if !satisfied_codes.contains(&normalize_code(code)) {
                    missing.push(code.clone());
                }
            }

            let satisfied = missing.is_empty();
            let notes = if satisfied {
                format!(
                    "All {} prerequisite course(s) satisfied or in progress.",
                    required.len()
                )
            } else {
                format!(
                    "Missing {} of {} prerequisite course(s) from catalog: {text}",
                    missing.len(),
                    required.len()
                )
            };

            Ok(PrerequisiteEvaluation {
                satisfied,
                missing_codes: missing,
                notes,
            })
        })
        .map_err(Into::into)
}

#[tauri::command]
pub fn academics_list_grading_categories(
    state: State<'_, AppState>,
    course_id: Option<String>,
) -> CmdResult<Vec<GradingCategoryDto>> {
    state.db.with_conn(|conn| {
        let mut out = Vec::new();
        if let Some(course_id) = course_id.filter(|s| !s.trim().is_empty()) {
            let mut stmt = conn.prepare(
                "SELECT id, course_id, name, weight, sort_order
                 FROM course_grading_category WHERE course_id = ?1 ORDER BY sort_order, name",
            )?;
            let rows = stmt.query_map(rusqlite::params![course_id], |r| {
                Ok(GradingCategoryDto {
                    id: r.get(0)?,
                    course_id: r.get(1)?,
                    name: r.get(2)?,
                    weight: r.get(3)?,
                    sort_order: r.get(4)?,
                })
            })?;
            out.extend(rows.filter_map(|r| r.ok()));
        } else {
            let mut stmt = conn.prepare(
                "SELECT id, course_id, name, weight, sort_order
                 FROM course_grading_category ORDER BY course_id, sort_order, name",
            )?;
            let rows = stmt.query_map([], |r| {
                Ok(GradingCategoryDto {
                    id: r.get(0)?,
                    course_id: r.get(1)?,
                    name: r.get(2)?,
                    weight: r.get(3)?,
                    sort_order: r.get(4)?,
                })
            })?;
            out.extend(rows.filter_map(|r| r.ok()));
        }
        Ok(out)
    })
    .map_err(Into::into)
}
