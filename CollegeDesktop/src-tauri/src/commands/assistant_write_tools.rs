//! Assistant write tools — prepare confirmed mutations (Swift write-tool parity).

use crate::commands::assistant::{detect_create_application, pending_action, AssistantPendingAction};
use crate::commands::CmdResult;
use crate::AppState;
use regex::Regex;
use rusqlite::OptionalExtension;
use tauri::{AppHandle, Emitter};

#[derive(Debug, Clone)]
pub struct WriteToolOutcome {
    pub summary: String,
    pub pending: Option<AssistantPendingAction>,
}

#[derive(Debug, Clone, serde::Serialize)]
#[serde(rename_all = "camelCase")]
struct AssistantNavigateEvent {
    module: String,
    page: String,
}

pub fn tool_label(name: &str) -> Option<&'static str> {
    match name {
        "create_task" => Some("Preparing task…"),
        "create_calendar_event" => Some("Preparing event…"),
        "add_course_to_plan" => Some("Preparing course add…"),
        "add_semester" => Some("Preparing semester…"),
        "remove_course_from_plan" => Some("Preparing course removal…"),
        "update_task" => Some("Preparing task update…"),
        "update_job_application_status" => Some("Preparing status update…"),
        "delete_task" => Some("Preparing task deletion…"),
        "delete_calendar_event" => Some("Preparing event deletion…"),
        "update_calendar_event" => Some("Preparing event update…"),
        "track_job_application" => Some("Preparing job tracker…"),
        "open_settings_section" => Some("Opening settings…"),
        "update_app_setting" => Some("Preparing setting change…"),
        "save_web_learning" => Some("Preparing memory save…"),
        "open_document" => Some("Opening document…"),
        "open_resume_builder" => Some("Opening resume builder…"),
        "update_profile" => Some("Preparing profile update…"),
        "sync_syllabus_deadlines" => Some("Preparing syllabus sync…"),
        "navigate_to_page" => Some("Navigating…"),
        _ => None,
    }
}

pub fn run_write_tool(
    app: &AppHandle,
    state: &AppState,
    name: &str,
    user_msg: &str,
) -> Option<CmdResult<WriteToolOutcome>> {
    let result = match name {
        "create_task" => prepare_create_task(user_msg),
        "create_calendar_event" => prepare_create_event(user_msg),
        "add_course_to_plan" => prepare_add_course(user_msg),
        "add_semester" => prepare_add_semester(user_msg),
        "remove_course_from_plan" => prepare_remove_course(user_msg),
        "update_task" => prepare_update_task(user_msg),
        "update_job_application_status" => prepare_update_application_status(user_msg),
        "delete_task" => prepare_delete_task(user_msg),
        "delete_calendar_event" => prepare_delete_event(user_msg),
        "update_calendar_event" => prepare_update_event(user_msg),
        "track_job_application" => prepare_track_application(user_msg),
        "open_settings_section" => prepare_open_settings(app, user_msg),
        "update_app_setting" => prepare_update_app_setting(user_msg),
        "save_web_learning" => prepare_save_web_learning(user_msg),
        "open_document" => prepare_open_document(app, state, user_msg),
        "open_resume_builder" => prepare_open_resume_builder(app, user_msg),
        "update_profile" => prepare_update_profile(user_msg),
        "sync_syllabus_deadlines" => prepare_sync_syllabus_deadlines(state),
        "navigate_to_page" => prepare_navigate(app, user_msg),
        _ => return None,
    };
    Some(result)
}

fn prepare_create_task(msg: &str) -> CmdResult<WriteToolOutcome> {
    let patterns = [
        r"(?i)^create task[:\s]+(.+)$",
        r"(?i)^add task[:\s]+(.+)$",
        r"(?i)^remind me to (.+)$",
        r"(?i)^new todo[:\s]+(.+)$",
    ];
    for pat in patterns {
        if let Ok(re) = Regex::new(pat) {
            if let Some(caps) = re.captures(msg.trim()) {
                let title = caps.get(1).map(|m| m.as_str().trim()).unwrap_or("");
                if !title.is_empty() {
                    return Ok(WriteToolOutcome {
                        summary: format!("Prepared task \"{title}\" for confirmation."),
                        pending: Some(pending_action("createTask", title)),
                    });
                }
            }
        }
    }
    Ok(WriteToolOutcome {
        summary: "Could not parse task title.".into(),
        pending: None,
    })
}

fn prepare_create_event(msg: &str) -> CmdResult<WriteToolOutcome> {
    let patterns = [
        r"(?i)^add event[:\s]+(.+)$",
        r"(?i)^create event[:\s]+(.+)$",
        r"(?i)^schedule[:\s]+(.+)$",
    ];
    for pat in patterns {
        if let Ok(re) = Regex::new(pat) {
            if let Some(caps) = re.captures(msg.trim()) {
                let title = caps.get(1).map(|m| m.as_str().trim()).unwrap_or("");
                if !title.is_empty() {
                    return Ok(WriteToolOutcome {
                        summary: format!("Prepared event \"{title}\" for confirmation."),
                        pending: Some(pending_action("createEvent", title)),
                    });
                }
            }
        }
    }
    Ok(WriteToolOutcome {
        summary: "Could not parse event title.".into(),
        pending: None,
    })
}

fn prepare_add_course(msg: &str) -> CmdResult<WriteToolOutcome> {
    let patterns = [
        r"(?i)add\s+(?:course\s+)?([A-Z]{2,4}\s?\d{2,4}[A-Z]?)\s+(?:to\s+)?(.+)$",
        r"(?i)add\s+([A-Z]{2,4}\s?\d{2,4}[A-Z]?)\s+to\s+(?:my\s+)?(?:plan|planner|semester)\s*(.*)$",
    ];
    for pat in patterns {
        if let Ok(re) = Regex::new(pat) {
            if let Some(caps) = re.captures(msg.trim()) {
                let code = caps.get(1).map(|m| m.as_str().trim()).unwrap_or("");
                let semester = caps.get(2).map(|m| m.as_str().trim()).unwrap_or("Current semester");
                if !code.is_empty() {
                    let mut action = pending_action("addCourseToPlan", code);
                    action.semester_name = Some(semester.to_string());
                    action.course_code = Some(code.to_string());
                    action.credits = Some(3.0);
                    return Ok(WriteToolOutcome {
                        summary: format!("Prepared adding {code} to {semester} for confirmation."),
                        pending: Some(action),
                    });
                }
            }
        }
    }
    Ok(WriteToolOutcome {
        summary: "Include a course code and semester, e.g. \"add CS 316 to Fall 2026\".".into(),
        pending: None,
    })
}

fn prepare_add_semester(msg: &str) -> CmdResult<WriteToolOutcome> {
    let re = Regex::new(r"(?i)add\s+(Fall|Spring|Summer|Winter)\s+(\d{4})(?:\s+semester)?").ok();
    if let Some(re) = re {
        if let Some(caps) = re.captures(msg.trim()) {
            let season = caps.get(1).map(|m| m.as_str()).unwrap_or("Fall");
            let year: i32 = caps
                .get(2)
                .and_then(|m| m.as_str().parse().ok())
                .unwrap_or(2026);
            let label = format!("{season} {year}");
            let mut action = pending_action("addSemester", &label);
            action.semester_name = Some(label.clone());
            action.year = Some(year);
            action.season = Some(season.to_string());
            return Ok(WriteToolOutcome {
                summary: format!("Prepared semester {label} for confirmation."),
                pending: Some(action),
            });
        }
    }
    Ok(WriteToolOutcome {
        summary: "Say e.g. \"add Fall 2026 semester\".".into(),
        pending: None,
    })
}

fn prepare_remove_course(msg: &str) -> CmdResult<WriteToolOutcome> {
    let re = Regex::new(r"(?i)remove\s+(?:course\s+)?([A-Z]{2,4}\s?\d{2,4}[A-Z]?)").ok();
    if let Some(re) = re {
        if let Some(caps) = re.captures(msg.trim()) {
            let code = caps.get(1).map(|m| m.as_str().trim()).unwrap_or("");
            if !code.is_empty() {
                let mut action = pending_action("removeCourseFromPlan", code);
                action.course_code = Some(code.to_string());
                return Ok(WriteToolOutcome {
                    summary: format!("Prepared removing {code} from plan for confirmation."),
                    pending: Some(action),
                });
            }
        }
    }
    Ok(WriteToolOutcome {
        summary: "Include a course code to remove.".into(),
        pending: None,
    })
}

fn prepare_update_task(msg: &str) -> CmdResult<WriteToolOutcome> {
    let re = Regex::new(r"(?i)update task\s+(.+?)\s+to\s+(.+)$").ok();
    if let Some(re) = re {
        if let Some(caps) = re.captures(msg.trim()) {
            let existing = caps.get(1).map(|m| m.as_str().trim()).unwrap_or("");
            let new_title = caps.get(2).map(|m| m.as_str().trim()).unwrap_or("");
            if !existing.is_empty() && !new_title.is_empty() {
                let mut action = pending_action("updateTask", new_title);
                action.existing_title = Some(existing.to_string());
                return Ok(WriteToolOutcome {
                    summary: format!("Prepared updating task \"{existing}\" → \"{new_title}\"."),
                    pending: Some(action),
                });
            }
        }
    }
    Ok(WriteToolOutcome {
        summary: "Say e.g. \"update task Essay Draft to Essay Final\".".into(),
        pending: None,
    })
}

fn prepare_update_application_status(msg: &str) -> CmdResult<WriteToolOutcome> {
    let re = Regex::new(
        r"(?i)(?:mark|move|set)\s+(.+?)\s+(?:as\s+|to\s+)?(interested|applied|interviewing|offer|rejected|accepted)",
    )
    .ok();
    if let Some(re) = re {
        if let Some(caps) = re.captures(msg.trim()) {
            let company = caps.get(1).map(|m| m.as_str().trim()).unwrap_or("");
            let status = caps.get(2).map(|m| m.as_str().to_ascii_lowercase()).unwrap_or_default();
            if !company.is_empty() {
                let mut action = pending_action("updateApplicationStatus", company);
                action.company = Some(company.to_string());
                action.status = Some(status.clone());
                return Ok(WriteToolOutcome {
                    summary: format!("Prepared moving {company} to {status}."),
                    pending: Some(action),
                });
            }
        }
    }
    Ok(WriteToolOutcome {
        summary: "Say e.g. \"mark Acme as interviewing\".".into(),
        pending: None,
    })
}

fn resolve_settings_section(msg: &str) -> Option<(String, String)> {
    let q = msg.to_lowercase();
    if !q.contains("setting") {
        return None;
    }
    if q.contains("privacy") || q.contains("security") {
        return Some(("settings".into(), "privacy".into()));
    }
    if q.contains("calendar") {
        return Some(("settings".into(), "calendar".into()));
    }
    if q.contains("document") {
        return Some(("settings".into(), "documents".into()));
    }
    if q.contains("career") {
        return Some(("settings".into(), "career".into()));
    }
    if q.contains("assistant") || q.contains("ai") {
        return Some(("settings".into(), "assistant".into()));
    }
    if q.contains("finance") {
        return Some(("settings".into(), "finance".into()));
    }
    if q.contains("lms") || q.contains("brightspace") {
        return Some(("settings".into(), "lms".into()));
    }
    if q.contains("shortcut") {
        return Some(("settings".into(), "shortcuts".into()));
    }
    if q.contains("profile") || q.contains("general") || q.contains("appearance") || q.contains("app") {
        return Some(("settings".into(), "app".into()));
    }
    Some(("settings".into(), "app".into()))
}

fn resolve_navigation(msg: &str) -> Option<(String, String)> {
    if let Some(nav) = resolve_settings_section(msg) {
        return Some(nav);
    }
    let q = msg.to_lowercase();
    if q.contains("calendar") || q.contains("schedule") {
        return Some(("calendar".into(), "month".into()));
    }
    if q.contains("planner") || q.contains("plan courses") {
        return Some(("college".into(), "planner".into()));
    }
    if q.contains("degree") || q.contains("requirement") {
        return Some(("college".into(), "degree".into()));
    }
    if q.contains("application") || q.contains("career") || q.contains("job") {
        return Some(("career".into(), "applications".into()));
    }
    if q.contains("document") || q.contains("vault") {
        return Some(("documents".into(), "all".into()));
    }
    if q.contains("profile") {
        return Some(("profile".into(), "identity".into()));
    }
    if q.contains("assistant") || q.contains("ask college") {
        return Some(("assistant".into(), "chat".into()));
    }
    if q.contains("resume") {
        return Some(("career".into(), "resume".into()));
    }
    if q.contains("finance") || q.contains("budget") {
        return Some(("finance".into(), "dashboard".into()));
    }
    if q.contains("transfer") {
        return Some(("college".into(), "transfer".into()));
    }
    if q.contains("catalog") || q.contains("course search") {
        return Some(("college".into(), "catalog".into()));
    }
    if q.contains("discovery") || q.contains("college search") {
        return Some(("college".into(), "discovery".into()));
    }
    if q.contains("overview") || q.contains("dashboard") {
        return Some(("college".into(), "academics".into()));
    }
    None
}

fn prepare_open_settings(app: &AppHandle, msg: &str) -> CmdResult<WriteToolOutcome> {
    let Some((module, page)) = resolve_settings_section(msg) else {
        return Ok(WriteToolOutcome {
            summary: "Try \"open settings calendar\" or \"settings privacy\".".into(),
            pending: None,
        });
    };
    let _ = app.emit(
        "assistant:navigate",
        AssistantNavigateEvent {
            module: module.clone(),
            page: page.clone(),
        },
    );
    Ok(WriteToolOutcome {
        summary: format!("Opened Settings → {page}."),
        pending: None,
    })
}

fn prepare_delete_task(msg: &str) -> CmdResult<WriteToolOutcome> {
    let patterns = [
        r"(?i)^delete task[:\s]+(.+)$",
        r"(?i)^remove task[:\s]+(.+)$",
        r"(?i)^delete todo[:\s]+(.+)$",
    ];
    for pat in patterns {
        if let Ok(re) = Regex::new(pat) {
            if let Some(caps) = re.captures(msg.trim()) {
                let title = caps.get(1).map(|m| m.as_str().trim()).unwrap_or("");
                if !title.is_empty() {
                    let mut action = pending_action("deleteTask", title);
                    action.existing_title = Some(title.to_string());
                    return Ok(WriteToolOutcome {
                        summary: format!("Prepared deleting task \"{title}\"."),
                        pending: Some(action),
                    });
                }
            }
        }
    }
    Ok(WriteToolOutcome {
        summary: "Say e.g. \"delete task Essay Draft\".".into(),
        pending: None,
    })
}

fn prepare_delete_event(msg: &str) -> CmdResult<WriteToolOutcome> {
    let patterns = [
        r"(?i)^delete event[:\s]+(.+)$",
        r"(?i)^remove event[:\s]+(.+)$",
        r"(?i)^cancel event[:\s]+(.+)$",
    ];
    for pat in patterns {
        if let Ok(re) = Regex::new(pat) {
            if let Some(caps) = re.captures(msg.trim()) {
                let title = caps.get(1).map(|m| m.as_str().trim()).unwrap_or("");
                if !title.is_empty() {
                    let mut action = pending_action("deleteCalendarEvent", title);
                    action.existing_title = Some(title.to_string());
                    return Ok(WriteToolOutcome {
                        summary: format!("Prepared deleting event \"{title}\"."),
                        pending: Some(action),
                    });
                }
            }
        }
    }
    Ok(WriteToolOutcome {
        summary: "Say e.g. \"delete event Meet advisor\".".into(),
        pending: None,
    })
}

fn prepare_update_event(msg: &str) -> CmdResult<WriteToolOutcome> {
    let re = Regex::new(r"(?i)update event\s+(.+?)\s+to\s+(.+)$").ok();
    if let Some(re) = re {
        if let Some(caps) = re.captures(msg.trim()) {
            let existing = caps.get(1).map(|m| m.as_str().trim()).unwrap_or("");
            let new_title = caps.get(2).map(|m| m.as_str().trim()).unwrap_or("");
            if !existing.is_empty() && !new_title.is_empty() {
                let mut action = pending_action("updateCalendarEvent", new_title);
                action.existing_title = Some(existing.to_string());
                return Ok(WriteToolOutcome {
                    summary: format!("Prepared updating event \"{existing}\" → \"{new_title}\"."),
                    pending: Some(action),
                });
            }
        }
    }
    Ok(WriteToolOutcome {
        summary: "Say e.g. \"update event Meet advisor to Advisor check-in\".".into(),
        pending: None,
    })
}

fn prepare_track_application(msg: &str) -> CmdResult<WriteToolOutcome> {
    if let Some(action) = detect_create_application(msg) {
        let company = action.company.clone().unwrap_or_default();
        let role = action
            .role_title
            .clone()
            .unwrap_or_else(|| action.title.clone());
        return Ok(WriteToolOutcome {
            summary: format!("Prepared tracking {role} at {company}."),
            pending: Some(action),
        });
    }
    Ok(WriteToolOutcome {
        summary: "Say e.g. \"track Software Engineer at Acme Corp\".".into(),
        pending: None,
    })
}

fn prepare_update_app_setting(msg: &str) -> CmdResult<WriteToolOutcome> {
    let lower = msg.to_lowercase();
    let (key, value, label) = if lower.contains("theme") {
        let value = if lower.contains("dark") {
            "dark"
        } else if lower.contains("light") {
            "light"
        } else {
            "system"
        };
        ("ui.theme", value, "Appearance theme")
    } else if lower.contains("reduce motion") {
        let value = if lower.contains("disable") || lower.contains("off") {
            "false"
        } else {
            "true"
        };
        ("ui.reduceMotion", value, "Reduce motion")
    } else {
        return Ok(WriteToolOutcome {
            summary: "Supported: \"set theme to dark\", \"enable reduce motion\".".into(),
            pending: None,
        });
    };
    let mut action = pending_action("updateAppSetting", label);
    action.setting_key = Some(key.to_string());
    action.setting_value = Some(value.to_string());
    Ok(WriteToolOutcome {
        summary: format!("Prepared setting {label} → {value}."),
        pending: Some(action),
    })
}

fn prepare_save_web_learning(msg: &str) -> CmdResult<WriteToolOutcome> {
    let patterns = [
        r"(?i)^remember that (.+)$",
        r"(?i)^save to memory[:\s]+(.+)$",
        r"(?i)^save this[:\s]+(.+)$",
        r"(?i)^remember[:\s]+(.+)$",
    ];
    for pat in patterns {
        if let Ok(re) = Regex::new(pat) {
            if let Some(caps) = re.captures(msg.trim()) {
                let body = caps.get(1).map(|m| m.as_str().trim()).unwrap_or("");
                if body.len() >= 8 {
                    let title: String = body.chars().take(48).collect();
                    let mut action = pending_action("saveWebLearning", &title);
                    action.summary_body = Some(body.to_string());
                    return Ok(WriteToolOutcome {
                        summary: "Prepared web memory save for confirmation.".into(),
                        pending: Some(action),
                    });
                }
            }
        }
    }
    Ok(WriteToolOutcome {
        summary: "Say e.g. \"remember that FAFSA opens October 1\".".into(),
        pending: None,
    })
}

#[derive(Debug, Clone, serde::Serialize)]
#[serde(rename_all = "camelCase")]
struct AssistantOpenDocumentEvent {
    document_id: String,
}

fn document_search_query(msg: &str) -> String {
    let patterns = [
        r"(?i)^open document[:\s]+(.+)$",
        r"(?i)^show document[:\s]+(.+)$",
        r"(?i)^open (.+) in documents$",
        r"(?i)^open (.+) in vault$",
    ];
    for pat in patterns {
        if let Ok(re) = Regex::new(pat) {
            if let Some(caps) = re.captures(msg.trim()) {
                if let Some(q) = caps.get(1) {
                    return q.as_str().trim().to_string();
                }
            }
        }
    }
    msg.trim().to_string()
}

fn prepare_open_document(
    app: &AppHandle,
    state: &AppState,
    msg: &str,
) -> CmdResult<WriteToolOutcome> {
    let query = document_search_query(msg);
    if query.len() < 2 {
        return Ok(WriteToolOutcome {
            summary: "Say e.g. \"open document FAFSA PDF\".".into(),
            pending: None,
        });
    }
    let like = format!("%{}%", query.replace('%', ""));
    let hit: Option<(String, String)> = state.db.with_conn(|conn| {
        conn.query_row(
            "SELECT id, title FROM vault_document
             WHERE is_folder = 0 AND title LIKE ?1
             ORDER BY updated_at DESC LIMIT 1",
            rusqlite::params![like],
            |r| Ok((r.get(0)?, r.get(1)?)),
        )
        .optional()
        .map_err(Into::into)
    })?;
    let Some((id, title)) = hit else {
        return Ok(WriteToolOutcome {
            summary: format!("No vault document matching \"{query}\"."),
            pending: None,
        });
    };
    let _ = app.emit(
        "assistant:navigate",
        AssistantNavigateEvent {
            module: "documents".into(),
            page: "all".into(),
        },
    );
    let _ = app.emit(
        "assistant:open-document",
        AssistantOpenDocumentEvent {
            document_id: id.clone(),
        },
    );
    Ok(WriteToolOutcome {
        summary: format!("Opened Documents → {title}."),
        pending: None,
    })
}

fn prepare_open_resume_builder(app: &AppHandle, _msg: &str) -> CmdResult<WriteToolOutcome> {
    let _ = app.emit(
        "assistant:navigate",
        AssistantNavigateEvent {
            module: "career".into(),
            page: "resume".into(),
        },
    );
    Ok(WriteToolOutcome {
        summary: "Opened Career → Resume builder.".into(),
        pending: None,
    })
}

fn prepare_sync_syllabus_deadlines(state: &AppState) -> CmdResult<WriteToolOutcome> {
    let drafts = crate::commands::assistant_tools_parity::syllabus_deadline_drafts(state)?;
    if drafts.is_empty() {
        return Ok(WriteToolOutcome {
            summary: "No syllabus deadlines to sync — add syllabus docs in Documents.".into(),
            pending: None,
        });
    }
    let payload: Vec<serde_json::Value> = drafts
        .iter()
        .map(|(title, due)| {
            serde_json::json!({
                "title": title,
                "dueAt": due,
            })
        })
        .collect();
    let json = serde_json::to_string(&payload).unwrap_or_else(|_| "[]".into());
    let mut action = pending_action(
        "syncSyllabusDeadlines",
        &format!("{} syllabus task(s)", drafts.len()),
    );
    action.summary_body = Some(json);
    Ok(WriteToolOutcome {
        summary: format!("Prepared {} syllabus task(s) for confirmation.", drafts.len()),
        pending: Some(action),
    })
}

fn prepare_update_profile(msg: &str) -> CmdResult<WriteToolOutcome> {
    let lower = msg.to_lowercase();
    let mut action = pending_action("updateProfile", "Profile update");
    let mut fields = 0usize;

    if let Ok(re) = Regex::new(r"(?i)(?:update|change)\s+my\s+name\s+to\s+(.+)$") {
        if let Some(caps) = re.captures(msg.trim()) {
            if let Some(name) = caps.get(1).map(|m| m.as_str().trim()).filter(|s| !s.is_empty()) {
                action.profile_name = Some(name.to_string());
                action.title = format!("Name → {name}");
                fields += 1;
            }
        }
    }
    if let Ok(re) = Regex::new(r"(?i)(?:update|change)\s+my\s+major\s+to\s+(.+)$") {
        if let Some(caps) = re.captures(msg.trim()) {
            if let Some(major) = caps.get(1).map(|m| m.as_str().trim()).filter(|s| !s.is_empty()) {
                action.profile_major = Some(major.to_string());
                action.title = format!("Major → {major}");
                fields += 1;
            }
        }
    }
    if let Ok(re) = Regex::new(r"(?i)(?:update|change)\s+my\s+(?:school|university)\s+to\s+(.+)$") {
        if let Some(caps) = re.captures(msg.trim()) {
            if let Some(school) = caps.get(1).map(|m| m.as_str().trim()).filter(|s| !s.is_empty()) {
                action.profile_university = Some(school.to_string());
                action.title = format!("School → {school}");
                fields += 1;
            }
        }
    }
    if let Ok(re) = Regex::new(r"(?i)(?:update|change)\s+my\s+email\s+to\s+(\S+)") {
        if let Some(caps) = re.captures(msg.trim()) {
            if let Some(email) = caps.get(1).map(|m| m.as_str().trim()).filter(|s| !s.is_empty()) {
                action.profile_email = Some(email.to_string());
                action.title = format!("Email → {email}");
                fields += 1;
            }
        }
    }

    if fields == 0 {
        return Ok(WriteToolOutcome {
            summary: "Say e.g. \"change my major to Computer Science\" or \"update my name to Alex\".".into(),
            pending: None,
        });
    }
    let _ = lower;
    Ok(WriteToolOutcome {
        summary: "Prepared profile update for confirmation.".into(),
        pending: Some(action),
    })
}

fn prepare_navigate(app: &AppHandle, msg: &str) -> CmdResult<WriteToolOutcome> {
    let Some((module, page)) = resolve_navigation(msg) else {
        return Ok(WriteToolOutcome {
            summary: "Try \"open calendar\", \"go to planner\", or \"show career applications\".".into(),
            pending: None,
        });
    };
    let _ = app.emit(
        "assistant:navigate",
        AssistantNavigateEvent {
            module: module.clone(),
            page: page.clone(),
        },
    );
    Ok(WriteToolOutcome {
        summary: format!("Navigating to {module} → {page}."),
        pending: None,
    })
}

pub fn plan_write_tools(q: &str) -> Vec<&'static str> {
    let lower = q.to_lowercase();
    let mut tools: Vec<&'static str> = Vec::new();
    let push = |name: &'static str, list: &mut Vec<&'static str>| {
        if !list.contains(&name) {
            list.push(name);
        }
    };

    if lower.contains("open ") || lower.contains("go to ") || lower.contains("show ") || lower.contains("navigate") {
        if lower.contains("setting") {
            push("open_settings_section", &mut tools);
        } else {
            push("navigate_to_page", &mut tools);
        }
    }
    if lower.contains("add task") || lower.contains("create task") || lower.contains("remind me") || lower.contains("new todo") {
        push("create_task", &mut tools);
    }
    if lower.contains("add event") || lower.contains("create event") || (lower.contains("schedule") && !lower.contains("schedule:")) {
        push("create_calendar_event", &mut tools);
    }
    if Regex::new(r"(?i)add\s+[a-z]{2,4}\s?\d")
        .ok()
        .map(|re| re.is_match(&lower))
        .unwrap_or(false)
    {
        push("add_course_to_plan", &mut tools);
    }
    if lower.contains("add fall") || lower.contains("add spring") || lower.contains("add semester") {
        push("add_semester", &mut tools);
    }
    if lower.contains("remove course") || (lower.contains("remove ") && lower.contains("from plan")) {
        push("remove_course_from_plan", &mut tools);
    }
    if lower.contains("update task") {
        push("update_task", &mut tools);
    }
    if lower.contains("update event") {
        push("update_calendar_event", &mut tools);
    }
    if lower.contains("delete task") || lower.contains("remove task") || lower.contains("delete todo") {
        push("delete_task", &mut tools);
    }
    if lower.contains("delete event") || lower.contains("remove event") || lower.contains("cancel event") {
        push("delete_calendar_event", &mut tools);
    }
    if (lower.contains("mark ") || lower.contains("move "))
        && (lower.contains("applied") || lower.contains("interview") || lower.contains("offer") || lower.contains("rejected"))
    {
        push("update_job_application_status", &mut tools);
    }
    if lower.contains("track job") || lower.contains("add job") || lower.contains("track application") {
        push("track_job_application", &mut tools);
    }
    if lower.contains("remember") || lower.contains("save to memory") || lower.contains("save this") {
        push("save_web_learning", &mut tools);
    }
    if (lower.contains("set theme") || lower.contains("change theme") || lower.contains("reduce motion"))
        && !lower.contains("setting")
    {
        push("update_app_setting", &mut tools);
    }
    if lower.contains("open document") || lower.contains("show document") || lower.contains(" in vault") {
        push("open_document", &mut tools);
    }
    if lower.contains("open resume") || lower.contains("resume builder") {
        push("open_resume_builder", &mut tools);
    }
    if lower.contains("sync syllabus") || lower.contains("syllabus deadlines to planner") {
        push("sync_syllabus_deadlines", &mut tools);
    }
    if lower.contains("change my major") || lower.contains("change my name") || lower.contains("update my email") {
        push("update_profile", &mut tools);
    }

    tools
}
