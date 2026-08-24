//! Remaining assistant tools — full Swift FM registry parity (read + prep helpers).

use crate::commands::assistant_tools_extended::{
    exec_get_full_time_status, exec_get_sap_status, extract_course_codes,
};
use crate::commands::CmdResult;
use crate::AppState;
use regex::Regex;
use rusqlite::OptionalExtension;

pub fn tool_label(name: &str) -> Option<&'static str> {
    match name {
        "draft_weekly_schedule" => Some("Drafting weekly schedule…"),
        "resolve_event_location" => Some("Resolving event location…"),
        "screen_aid_eligibility" => Some("Screening aid eligibility…"),
        "estimate_aid_range" => Some("Estimating aid range…"),
        "extract_aid_document_facts" => Some("Reading aid doc checklist…"),
        "compare_award_letter_to_planner" => Some("Comparing award letter…"),
        "assess_requirement_risk" => Some("Assessing requirement risk…"),
        "simulate_course_swap" => Some("Simulating course swap…"),
        "suggest_courses_for_skill_gaps" => Some("Suggesting courses…"),
        "assess_registration_workload" => Some("Assessing workload…"),
        "propose_syllabus_deadline_sync" => Some("Reading syllabus deadlines…"),
        _ => None,
    }
}

pub fn run_parity_tool(state: &AppState, name: &str, user_msg: &str) -> Option<CmdResult<String>> {
    let result = match name {
        "draft_weekly_schedule" => exec_draft_weekly_schedule(state),
        "resolve_event_location" => exec_resolve_event_location(state, user_msg),
        "screen_aid_eligibility" => exec_screen_aid_eligibility(state, user_msg),
        "estimate_aid_range" => exec_estimate_aid_range(user_msg),
        "extract_aid_document_facts" => exec_extract_aid_document_facts(),
        "compare_award_letter_to_planner" => exec_compare_award_letter_to_planner(state),
        "assess_requirement_risk" => exec_assess_requirement_risk(state),
        "simulate_course_swap" => exec_simulate_course_swap(state, user_msg),
        "suggest_courses_for_skill_gaps" => exec_suggest_courses_for_skill_gaps(state, user_msg),
        "assess_registration_workload" => exec_assess_registration_workload(state, user_msg),
        "propose_syllabus_deadline_sync" => exec_propose_syllabus_deadline_sync(state),
        _ => return None,
    };
    Some(result)
}

pub fn syllabus_deadline_drafts(state: &AppState) -> CmdResult<Vec<(String, Option<String>)>> {
    // Prefer last Syllabus Review analysis (assistant.syllabusDeadlineDrafts.v1).
    if let Ok(Some(raw)) = state.db.with_conn(|conn| {
        conn.query_row(
            "SELECT value FROM app_settings WHERE key = 'assistant.syllabusDeadlineDrafts.v1' LIMIT 1",
            [],
            |r| r.get::<_, String>(0),
        )
        .optional()
        .map_err(Into::into)
    }) {
        if let Ok(parsed) = serde_json::from_str::<Vec<serde_json::Value>>(&raw) {
            let mut out = Vec::new();
            for item in parsed.into_iter().take(24) {
                let title = item
                    .get("title")
                    .and_then(|v| v.as_str())
                    .unwrap_or("")
                    .trim()
                    .to_string();
                if title.is_empty() {
                    continue;
                }
                let due = item
                    .get("dueAt")
                    .and_then(|v| v.as_str())
                    .map(|s| s.to_string())
                    .filter(|s| !s.trim().is_empty());
                let course = item
                    .get("courseCode")
                    .and_then(|v| v.as_str())
                    .filter(|s| !s.is_empty());
                let labeled = if let Some(code) = course {
                    format!("{code}: {title}")
                } else {
                    title
                };
                out.push((labeled, due));
            }
            if !out.is_empty() {
                return Ok(out);
            }
        }
    }

    state
        .db
        .with_conn(|conn| {
            let mut stmt = conn.prepare(
                "SELECT title FROM vault_document
                 WHERE is_folder = 0 AND (
                   lower(category) LIKE '%syllabus%' OR lower(title) LIKE '%syllabus%'
                 )
                 ORDER BY updated_at DESC LIMIT 24",
            )?;
            let mut out = Vec::new();
            let rows = stmt.query_map([], |r| r.get::<_, String>(0))?;
            for row in rows {
                let title = row?;
                let task_title = if title.to_lowercase().contains("deadline") {
                    title.clone()
                } else {
                    format!("{title} — review deadline")
                };
                out.push((task_title, None));
            }
            Ok(out)
        })
        .map_err(|e| crate::commands::CommandError {
            message: e.to_string(),
        })
}

fn exec_draft_weekly_schedule(state: &AppState) -> CmdResult<String> {
    let (event_count, task_count): (i64, i64) = state.db.with_conn(|conn| {
        let events: i64 = conn
            .query_row(
                "SELECT COUNT(*) FROM calendar_event
                 WHERE start_at >= datetime('now') AND start_at <= datetime('now', '+7 days')",
                [],
                |r| r.get(0),
            )
            .unwrap_or(0);
        let tasks: i64 = conn
            .query_row(
                "SELECT COUNT(*) FROM planner_task
                 WHERE is_complete = 0 AND due_at IS NOT NULL
                   AND due_at <= datetime('now', '+7 days')",
                [],
                |r| r.get(0),
            )
            .unwrap_or(0);
        Ok((events, tasks))
    })?;
    Ok(format!(
        "Weekly draft (read-only): {event_count} event(s) and {task_count} due task(s) in the next 7 days. \
         Suggested blocks: two 60–90 min study sessions for your hardest course; prioritize due-soon tasks; \
         leave a buffer for meals and catch-up. Use create_task / create_calendar_event after you pick times."
    ))
}

fn exec_resolve_event_location(state: &AppState, user_msg: &str) -> CmdResult<String> {
    let query = user_msg
        .replace("where is", "")
        .replace("location of", "")
        .trim()
        .to_string();
    let like = format!("%{}%", query.replace('%', ""));
    let row: Option<(String, String, Option<String>, Option<String>)> = state.db.with_conn(|conn| {
        conn.query_row(
            "SELECT title, start_at, location, notes FROM calendar_event
             WHERE title LIKE ?1 AND start_at >= datetime('now')
             ORDER BY start_at ASC LIMIT 1",
            rusqlite::params![like],
            |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?)),
        )
        .optional()
        .map_err(Into::into)
    })?;
    let Some((title, start, location, notes)) = row else {
        return Ok(format!("No upcoming event matched \"{query}\"."));
    };
    let loc = location.unwrap_or_default();
    if loc.trim().is_empty() {
        return Ok(format!(
            "Found \"{title}\" @ {start} but no location saved. Offer update_calendar_event to add a room."
        ));
    }
    let note = notes.filter(|n| !n.trim().is_empty()).unwrap_or_default();
    Ok(format!(
        "\"{title}\" @ {start} is at {loc}.{}",
        if note.is_empty() {
            String::new()
        } else {
            format!(" Notes: {note}")
        }
    ))
}

fn exec_screen_aid_eligibility(state: &AppState, user_msg: &str) -> CmdResult<String> {
    let lower = user_msg.to_lowercase();
    let program = if lower.contains("pell") {
        "Pell Grant"
    } else if lower.contains("tap") || lower.contains("state") {
        "state aid"
    } else if lower.contains("fafsa") {
        "FAFSA"
    } else {
        "general aid"
    };
    let full_time = exec_get_full_time_status(state, user_msg)?;
    Ok(format!(
        "Aid screening for {program} (checklist only, not an official decision): \
         verify degree-seeking status, enrollment intensity, SAP standing, and application status. \
         Do not share SSN or FSA ID. {full_time}"
    ))
}

fn exec_estimate_aid_range(user_msg: &str) -> CmdResult<String> {
    let coa_re = Regex::new(r"(?i)(?:coa|cost of attendance)[^\d]*(\d[\d,]*)").ok();
    let sai_re = Regex::new(r"(?i)sai[^\d]*(\d[\d,]*)").ok();
    let parse_num = |s: &str| s.replace(',', "").parse::<f64>().ok();
    let coa = coa_re
        .and_then(|re| re.captures(user_msg))
        .and_then(|c| c.get(1))
        .and_then(|m| parse_num(m.as_str()));
    let sai = sai_re
        .and_then(|re| re.captures(user_msg))
        .and_then(|c| c.get(1))
        .and_then(|m| parse_num(m.as_str()));
    if let (Some(coa), Some(sai)) = (coa, sai) {
        let need = (coa - sai).max(0.0);
        return Ok(format!(
            "Planning estimate (not an official award): need framework up to ~${need:.0} before program rules and packaging."
        ));
    }
    Ok(
        "Provide COA and SAI for a numeric planning estimate — e.g. \"COA 24000 SAI 1200\". \
         This is not an official FAFSA or school award."
            .into(),
    )
}

fn exec_extract_aid_document_facts() -> CmdResult<String> {
    Ok(
        "Aid document checklist: extract aid year, grants/scholarships, loans, work-study, estimated cost, \
         missing documents, deadlines, and required actions. Attach the PDF in Assistant and ask what each line means. \
         Processed locally — do not upload government IDs."
            .into(),
    )
}

fn exec_compare_award_letter_to_planner(state: &AppState) -> CmdResult<String> {
    let sap = exec_get_sap_status(state)?;
    let major: String = state.db.with_conn(|conn| {
        Ok(conn
            .query_row(
                "SELECT major FROM profile ORDER BY updated_at DESC LIMIT 1",
                [],
                |r| r.get::<_, String>(0),
            )
            .unwrap_or_default())
    })?;
    let prog = if major.trim().is_empty() {
        "not set in profile".into()
    } else {
        major
    };
    Ok(format!(
        "Award letter review vs planner: confirm full-time assumption, separate loans from grants, verify aid year matches your term, \
         check pending verification. Programs tracked: {prog}. {sap} Questions for aid office: Is this final? What if credits change?"
    ))
}

fn exec_assess_requirement_risk(state: &AppState) -> CmdResult<String> {
    let rows: Vec<(String, String, Option<String>)> = state.db.with_conn(|conn| {
        let mut stmt = conn.prepare(
            "SELECT c.code, c.title, cat.prerequisites FROM planner_course c
             LEFT JOIN course_catalog cat ON UPPER(cat.code) = UPPER(c.code)
             WHERE c.status NOT IN ('completed', 'dropped')
             ORDER BY c.credits DESC LIMIT 8",
        )?;
        let mut out = Vec::new();
        for row in stmt.query_map([], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)))? {
            out.push(row?);
        }
        Ok(out)
    })?;
    if rows.is_empty() {
        return Ok(
            "No pending planner courses to assess — add planned courses in Degree/Planner first.".into(),
        );
    }
    let mut scored: Vec<(i32, String)> = rows
        .into_iter()
        .map(|(code, title, prereq)| {
            let mut score = 45;
            let mut reasons = Vec::new();
            if let Some(p) = prereq.filter(|s| !s.trim().is_empty()) {
                score += 25;
                reasons.push(format!("prereqs: {p}"));
            }
            reasons.push("pending on plan".into());
            (score, format!("{code} {title} (risk {score}/100: {})", reasons.join("; ")))
        })
        .collect();
    scored.sort_by(|a, b| b.0.cmp(&a.0));
    let top: Vec<_> = scored.into_iter().take(5).map(|(_, s)| s).collect();
    Ok(format!(
        "Requirement risk (read-only): {}. Confirm sequencing with your advisor.",
        top.join(" · ")
    ))
}

fn exec_simulate_course_swap(state: &AppState, user_msg: &str) -> CmdResult<String> {
    let re = Regex::new(r"(?i)swap\s+([A-Z]{2,4}\s?\d{2,4}[A-Z]?)\s+(?:for|with)\s+([A-Z]{2,4}\s?\d{2,4}[A-Z]?)").ok();
    let (remove, add) = if let Some(re) = re {
        if let Some(caps) = re.captures(user_msg) {
            (
                caps.get(1).map(|m| m.as_str().trim()).unwrap_or("").to_string(),
                caps.get(2).map(|m| m.as_str().trim()).unwrap_or("").to_string(),
            )
        } else {
            (String::new(), String::new())
        }
    } else {
        let codes = extract_course_codes(user_msg);
        if codes.len() >= 2 {
            (codes[0].clone(), codes[1].clone())
        } else {
            (String::new(), String::new())
        }
    };
    if remove.is_empty() || add.is_empty() {
        return Ok("Say e.g. \"simulate swap CS 316 for CS 414\".".into());
    }
    let titles: (Option<String>, Option<String>) = state.db.with_conn(|conn| {
        let t1: Option<String> = conn
            .query_row(
                "SELECT title FROM course_catalog WHERE UPPER(code) = UPPER(?1) LIMIT 1",
                rusqlite::params![&remove],
                |r| r.get(0),
            )
            .optional()?;
        let t2: Option<String> = conn
            .query_row(
                "SELECT title FROM course_catalog WHERE UPPER(code) = UPPER(?1) LIMIT 1",
                rusqlite::params![&add],
                |r| r.get(0),
            )
            .optional()?;
        Ok((t1, t2))
    })?;
    Ok(format!(
        "What-if swap (no planner changes): remove {remove} ({}) → add {add} ({}). \
         Review prerequisites and career narrative before registering.",
        titles.0.unwrap_or_else(|| "unknown title".into()),
        titles.1.unwrap_or_else(|| "unknown title".into())
    ))
}

fn exec_suggest_courses_for_skill_gaps(state: &AppState, user_msg: &str) -> CmdResult<String> {
    let skills: Vec<&str> = user_msg
        .split_whitespace()
        .filter(|w| w.len() > 4)
        .take(3)
        .collect();
    let needle = if skills.is_empty() {
        "data".to_string()
    } else {
        skills.join(" ")
    };
    let like = format!("%{}%", needle.replace('%', ""));
    let hits: Vec<String> = state.db.with_conn(|conn| {
        let mut stmt = conn.prepare(
            "SELECT code, title FROM course_catalog
             WHERE title LIKE ?1 OR description LIKE ?1
             ORDER BY code ASC LIMIT 5",
        )?;
        let mut out = Vec::new();
        for row in stmt.query_map(rusqlite::params![like], |r| {
            Ok(format!("{} — {}", r.get::<_, String>(0)?, r.get::<_, String>(1)?))
        })? {
            out.push(row?);
        }
        Ok(out)
    })?;
    if hits.is_empty() {
        return Ok(format!("No catalog matches for skill gap \"{needle}\"."));
    }
    Ok(format!(
        "Skill-gap suggestions (confirm prereqs): {}.",
        hits.join("; ")
    ))
}

fn exec_assess_registration_workload(state: &AppState, user_msg: &str) -> CmdResult<String> {
    let credits_re = Regex::new(r"(\d{1,2})\s*credits?").ok();
    let credits: i64 = credits_re
        .and_then(|re| re.captures(user_msg))
        .and_then(|c| c.get(1))
        .and_then(|m| m.as_str().parse().ok())
        .unwrap_or(15)
        .clamp(1, 24);
    let (tasks, events): (i64, i64) = state.db.with_conn(|conn| {
        let tasks: i64 = conn
            .query_row(
                "SELECT COUNT(*) FROM planner_task
                 WHERE is_complete = 0 AND due_at >= datetime('now')
                   AND due_at <= datetime('now', '+30 days')",
                [],
                |r| r.get(0),
            )
            .unwrap_or(0);
        let events: i64 = conn
            .query_row(
                "SELECT COUNT(*) FROM calendar_event
                 WHERE start_at >= datetime('now') AND start_at <= datetime('now', '+30 days')",
                [],
                |r| r.get(0),
            )
            .unwrap_or(0);
        Ok((tasks, events))
    })?;
    let syllabus_count: i64 = state.db.with_conn(|conn| {
        Ok(conn
            .query_row(
                "SELECT COUNT(*) FROM vault_document
                 WHERE is_folder = 0 AND lower(category) LIKE '%syllabus%'",
                [],
                |r| r.get(0),
            )
            .unwrap_or(0))
    })?;
    let mut level = "moderate";
    if credits >= 18 || tasks + events >= 10 {
        level = "heavy";
    } else if syllabus_count > 0 {
        level = "elevated";
    }
    Ok(format!(
        "Registration workload for {credits} credits: {level}. Next 30 days — {events} events, {tasks} tasks, {syllabus_count} syllabus doc(s) on file."
    ))
}

fn exec_propose_syllabus_deadline_sync(state: &AppState) -> CmdResult<String> {
    let drafts = syllabus_deadline_drafts(state)?;
    if drafts.is_empty() {
        return Ok("No syllabus deadline drafts — add syllabus PDFs in Documents (syllabus category).".into());
    }
    let preview: Vec<_> = drafts
        .iter()
        .take(6)
        .map(|(t, _)| t.as_str())
        .collect();
    Ok(format!(
        "Syllabus deadline drafts ({} total, read-only): {}. Say \"sync syllabus deadlines\" to confirm task creation.",
        drafts.len(),
        preview.join("; ")
    ))
}
