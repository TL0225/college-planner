//! Extended read-only assistant tools — Swift `AIAssistant*Tools` parity subset.

use crate::commands::CmdResult;
use crate::AppState;
use regex::Regex;
use rusqlite::OptionalExtension;

pub fn tool_label(name: &str) -> Option<&'static str> {
    match name {
        "get_student_profile" => Some("Reading profile…"),
        "get_program_progress" => Some("Reading program progress…"),
        "get_upcoming_schedule" => Some("Reading upcoming schedule…"),
        "semantic_catalog_search" => Some("Semantic catalog search…"),
        "check_prerequisites" => Some("Checking prerequisites…"),
        "explain_requirements" => Some("Explaining requirements…"),
        "list_career_resumes" => Some("Reading resumes…"),
        "get_job_application_detail" => Some("Reading application…"),
        "compute_arithmetic" => Some("Computing…"),
        "get_app_setting" => Some("Reading setting…"),
        "list_saved_schools" => Some("Reading saved schools…"),
        "list_programs_under_department" => Some("Listing programs…"),
        "get_aid_deadlines" => Some("Reading aid deadlines…"),
        "list_brag_entries" => Some("Reading highlights…"),
        "list_network_contacts" => Some("Reading network…"),
        "assess_registration_readiness" => Some("Assessing registration…"),
        "get_document_excerpt" => Some("Reading document…"),
        "get_sap_status" => Some("Reading SAP status…"),
        "get_full_time_status" => Some("Checking full-time status…"),
        "get_job_resume_match" => Some("Reading resume match…"),
        "get_student_learning_profile" => Some("Reading learning profile…"),
        "explain_sap_policy" => Some("Explaining SAP policy…"),
        "draft_semester_plan" => Some("Drafting semester plan…"),
        _ => None,
    }
}

pub fn run_extended_tool(state: &AppState, name: &str, user_msg: &str) -> Option<CmdResult<String>> {
    let result = match name {
        "get_student_profile" | "get_profile" => exec_get_student_profile(state),
        "get_program_progress" => exec_get_program_progress(state),
        "get_upcoming_schedule" => exec_get_upcoming_schedule(state),
        "semantic_catalog_search" => exec_semantic_catalog_search(state, user_msg),
        "check_prerequisites" => exec_check_prerequisites(state, user_msg),
        "explain_requirements" => exec_explain_requirements(state),
        "list_career_resumes" => exec_list_career_resumes(state),
        "get_job_application_detail" => exec_get_job_application_detail(state, user_msg),
        "compute_arithmetic" => exec_compute_arithmetic(user_msg),
        "get_app_setting" => exec_get_app_setting(state, user_msg),
        "list_saved_schools" => exec_list_saved_schools(state),
        "list_programs_under_department" => exec_list_programs_under_department(state),
        "get_aid_deadlines" => exec_get_aid_deadlines(state),
        "list_brag_entries" => exec_list_brag_entries(state),
        "list_network_contacts" => exec_list_network_contacts(state),
        "assess_registration_readiness" => exec_assess_registration_readiness(state),
        "get_document_excerpt" => exec_get_document_excerpt(state, user_msg),
        "get_sap_status" => exec_get_sap_status(state),
        "get_full_time_status" => exec_get_full_time_status(state, user_msg),
        "get_job_resume_match" => exec_get_job_resume_match(state, user_msg),
        "get_student_learning_profile" => exec_get_student_learning_profile(state),
        "explain_sap_policy" => exec_explain_sap_policy(state),
        "draft_semester_plan" => exec_draft_semester_plan(state, user_msg),
        _ => return None,
    };
    Some(result)
}

fn keyword_tokens(text: &str) -> std::collections::HashSet<String> {
    text.split(|c: char| !c.is_alphanumeric())
        .map(|t| t.to_ascii_lowercase())
        .filter(|t| t.len() > 2)
        .collect()
}

fn resume_match_score(resume: &str, job: &str) -> (i32, Vec<String>, Vec<String>) {
    let resume_tokens = keyword_tokens(resume);
    let job_tokens = keyword_tokens(job);
    if job_tokens.is_empty() {
        return (0, vec![], vec![]);
    }
    let mut matched = Vec::new();
    let mut missing = Vec::new();
    for term in &job_tokens {
        if resume_tokens.contains(term) {
            matched.push(term.clone());
        } else {
            missing.push(term.clone());
        }
    }
    matched.sort();
    missing.sort();
    let score = ((matched.len() as f64 / job_tokens.len() as f64) * 100.0).round() as i32;
    (score, matched, missing)
}

fn exec_get_student_profile(state: &AppState) -> CmdResult<String> {
    let row: Option<(String, String, String, String)> = state.db.with_conn(|conn| {
        conn.query_row(
            "SELECT full_name, email, university_name, major FROM profile ORDER BY updated_at DESC LIMIT 1",
            [],
            |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?)),
        )
        .optional()
        .map_err(Into::into)
    })?;
    let Some((name, email, school, major)) = row else {
        return Ok("No profile identity saved yet.".into());
    };
    Ok(format!(
        "Profile: {name} · {email} · {school} · major {major}",
        name = name.trim(),
        email = email.trim(),
        school = school.trim(),
        major = major.trim()
    ))
}

fn exec_get_program_progress(state: &AppState) -> CmdResult<String> {
    let (completed, planned, sections): (f64, f64, i64) = state.db.with_conn(|conn| {
        let completed: f64 = conn
            .query_row(
                "SELECT COALESCE(SUM(credits), 0) FROM planner_course WHERE status = 'completed'",
                [],
                |r| r.get(0),
            )
            .unwrap_or(0.0);
        let planned: f64 = conn
            .query_row(
                "SELECT COALESCE(SUM(credits), 0) FROM planner_course WHERE status != 'dropped'",
                [],
                |r| r.get(0),
            )
            .unwrap_or(0.0);
        let sections: i64 = conn
            .query_row(
                "SELECT COUNT(DISTINCT section_title) FROM catalog_degree_requirement",
                [],
                |r| r.get(0),
            )
            .unwrap_or(0);
        Ok((completed, planned, sections))
    })?;
    Ok(format!(
        "Program progress: {completed:.1} completed credits, {planned:.1} total planned, {sections} requirement sections tracked.",
        completed = completed,
        planned = planned,
        sections = sections
    ))
}

fn exec_get_upcoming_schedule(state: &AppState) -> CmdResult<String> {
    let lines: Vec<String> = state.db.with_conn(|conn| {
        let mut stmt = conn.prepare(
            "SELECT title, start_at FROM calendar_event
             WHERE start_at >= datetime('now')
             ORDER BY start_at ASC LIMIT 10",
        )?;
        let mut out = Vec::new();
        let rows = stmt.query_map([], |r| Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?)))?;
        for row in rows {
            let (title, start) = row?;
            out.push(format!("{title} @ {start}"));
        }
        Ok(out)
    })?;
    if lines.is_empty() {
        return Ok("No upcoming events on your schedule.".into());
    }
    Ok(format!("Upcoming schedule: {}", lines.join("; ")))
}

fn exec_semantic_catalog_search(state: &AppState, query: &str) -> CmdResult<String> {
    let q = query.trim();
    if q.is_empty() {
        return Ok("Provide a catalog search query.".into());
    }
    let like = format!("%{}%", q.replace('%', ""));
    let hits: Vec<String> = state.db.with_conn(|conn| {
        let mut stmt = conn.prepare(
            "SELECT code, title FROM course_catalog
             WHERE code LIKE ?1 OR title LIKE ?1 OR description LIKE ?1
             ORDER BY code ASC LIMIT 10",
        )?;
        let mut out = Vec::new();
        let rows = stmt.query_map(rusqlite::params![like], |r| {
            Ok(format!("{} — {}", r.get::<_, String>(0)?, r.get::<_, String>(1)?))
        })?;
        for row in rows {
            out.push(row?);
        }
        Ok(out)
    })?;
    if hits.is_empty() {
        return Ok(format!("No semantic catalog hits for \"{q}\"."));
    }
    Ok(format!("Catalog semantic matches: {}", hits.join("; ")))
}

pub(crate) fn extract_course_codes(text: &str) -> Vec<String> {
    let re = Regex::new(r"\b[A-Z]{2,4}\s?\d{2,4}[A-Z]?\b").ok();
    let Some(re) = re else {
        return vec![];
    };
    re.find_iter(text)
        .map(|m| m.as_str().replace(' ', " "))
        .collect()
}

fn exec_check_prerequisites(state: &AppState, user_msg: &str) -> CmdResult<String> {
    let codes = extract_course_codes(user_msg);
    if codes.is_empty() {
        return Ok("Include a course code (e.g. CS 101) to check prerequisites.".into());
    }
    let code = codes[0].to_uppercase();
    let prereq: Option<String> = state.db.with_conn(|conn| {
        conn.query_row(
            "SELECT prerequisites FROM course_catalog WHERE UPPER(code) = UPPER(?1) LIMIT 1",
            rusqlite::params![code],
            |r| r.get(0),
        )
        .optional()
        .map_err(Into::into)
    })?;
    match prereq.filter(|s| !s.trim().is_empty()) {
        Some(p) => Ok(format!("Prerequisites for {code}: {p}")),
        None => Ok(format!("No prerequisite data on file for {code}.")),
    }
}

fn exec_explain_requirements(state: &AppState) -> CmdResult<String> {
    let sections: Vec<String> = state.db.with_conn(|conn| {
        let mut stmt = conn.prepare(
            "SELECT section_title, COUNT(*) FROM catalog_degree_requirement
             GROUP BY section_title ORDER BY section_title ASC LIMIT 8",
        )?;
        let mut out = Vec::new();
        let rows = stmt.query_map([], |r| {
            Ok(format!("{} ({} rules)", r.get::<_, String>(0)?, r.get::<_, i64>(1)?))
        })?;
        for row in rows {
            out.push(row?);
        }
        Ok(out)
    })?;
    if sections.is_empty() {
        return Ok("No requirement sections loaded — add a program or load sample data.".into());
    }
    Ok(format!("Requirement sections: {}", sections.join("; ")))
}

fn exec_list_career_resumes(state: &AppState) -> CmdResult<String> {
    let rows: Vec<String> = state.db.with_conn(|conn| {
        let mut stmt = conn.prepare(
            "SELECT target_role, target_company, notes FROM career_resume_profile
             ORDER BY updated_at DESC LIMIT 8",
        )?;
        let mut out = Vec::new();
        let mapped = stmt.query_map([], |r| {
            let role: String = r.get(0)?;
            let company: String = r.get(1)?;
            Ok(format!("{role} @ {company}"))
        })?;
        for row in mapped {
            out.push(row?);
        }
        Ok(out)
    })?;
    if rows.is_empty() {
        return Ok("No saved resume profiles.".into());
    }
    Ok(format!("Resume profiles: {}", rows.join("; ")))
}

fn exec_get_job_application_detail(state: &AppState, user_msg: &str) -> CmdResult<String> {
    let like = format!("%{}%", user_msg.replace('%', ""));
    let row: Option<(String, String, String, String)> = state.db.with_conn(|conn| {
        conn.query_row(
            "SELECT company, role_title, status, COALESCE(url, '')
             FROM job_application
             WHERE company LIKE ?1 OR role_title LIKE ?1
             ORDER BY updated_at DESC LIMIT 1",
            rusqlite::params![like],
            |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?)),
        )
        .optional()
        .map_err(Into::into)
    })?;
    let Some((company, role, status, url)) = row else {
        return Ok("No matching job application found.".into());
    };
    Ok(format!(
        "Application: {company} — {role} ({status}){}",
        if url.is_empty() {
            String::new()
        } else {
            format!(" · {url}")
        }
    ))
}

fn exec_compute_arithmetic(user_msg: &str) -> CmdResult<String> {
    let re = Regex::new(r"(-?\d+(?:\.\d+)?)\s*([+\-*/])\s*(-?\d+(?:\.\d+)?)").ok();
    let Some(re) = re else {
        return Ok("Could not parse arithmetic.".into());
    };
    let Some(caps) = re.captures(user_msg) else {
        return Ok("Include a simple expression like 3 + 4 or 12 * 2.".into());
    };
    let a: f64 = caps.get(1).and_then(|m| m.as_str().parse().ok()).unwrap_or(0.0);
    let op = caps.get(2).map(|m| m.as_str()).unwrap_or("+");
    let b: f64 = caps.get(3).and_then(|m| m.as_str().parse().ok()).unwrap_or(0.0);
    let result = match op {
        "+" => a + b,
        "-" => a - b,
        "*" => a * b,
        "/" if b != 0.0 => a / b,
        "/" => {
            return Ok("Division by zero.".into());
        }
        _ => a + b,
    };
    Ok(format!("Result: {result}"))
}

fn exec_get_app_setting(state: &AppState, user_msg: &str) -> CmdResult<String> {
    let key = user_msg
        .split_whitespace()
        .find(|w| w.contains('.'))
        .unwrap_or("shell.theme");
    let value: String = state.db.with_conn(|conn| {
        Ok(conn
            .query_row(
                "SELECT value FROM app_settings WHERE key = ?1 LIMIT 1",
                rusqlite::params![key],
                |r| r.get(0),
            )
            .unwrap_or_default())
    })?;
    Ok(format!("Setting {key} = {value}"))
}

fn exec_list_saved_schools(state: &AppState) -> CmdResult<String> {
    let names: Vec<String> = state.db.with_conn(|conn| {
        let mut stmt = conn.prepare(
            "SELECT name FROM discovery_institution_identity WHERE is_saved = 1 ORDER BY name ASC LIMIT 12",
        )?;
        let mut out = Vec::new();
        let rows = stmt.query_map([], |r| r.get(0))?;
        for row in rows {
            out.push(row?);
        }
        Ok(out)
    })?;
    if names.is_empty() {
        return Ok("No saved discovery schools.".into());
    }
    Ok(format!("Saved schools: {}", names.join(", ")))
}

fn exec_list_programs_under_department(state: &AppState) -> CmdResult<String> {
    let rows: Vec<String> = state.db.with_conn(|conn| {
        let mut stmt = conn.prepare(
            "SELECT d.code, d.name,
                    (SELECT COUNT(1) FROM course_catalog c WHERE c.department_id = d.id) AS course_count
             FROM department d
             ORDER BY d.code ASC LIMIT 12",
        )?;
        let mut out = Vec::new();
        let mapped = stmt.query_map([], |r| {
            Ok(format!(
                "{} · {} ({} courses)",
                r.get::<_, String>(0)?,
                r.get::<_, String>(1)?,
                r.get::<_, i64>(2)?
            ))
        })?;
        for row in mapped {
            out.push(row?);
        }
        Ok(out)
    })?;
    if rows.is_empty() {
        return Ok("No catalog departments — run ingest or sample seed.".into());
    }
    Ok(format!("Departments: {}", rows.join("; ")))
}

fn exec_get_aid_deadlines(state: &AppState) -> CmdResult<String> {
    let lines: Vec<String> = state.db.with_conn(|conn| {
        let mut stmt = conn.prepare(
            "SELECT title, due_at FROM planner_task
             WHERE is_complete = 0 AND (
               LOWER(title) LIKE '%fafsa%' OR LOWER(title) LIKE '%aid%' OR LOWER(title) LIKE '%scholarship%'
             )
             ORDER BY due_at IS NULL, due_at ASC LIMIT 8",
        )?;
        let mut out = Vec::new();
        let rows = stmt.query_map([], |r| {
            let title: String = r.get(0)?;
            let due: Option<String> = r.get(1)?;
            Ok(if let Some(d) = due {
                format!("{title} (due {d})")
            } else {
                title
            })
        })?;
        for row in rows {
            out.push(row?);
        }
        Ok(out)
    })?;
    if lines.is_empty() {
        return Ok("No aid-related task deadlines on file.".into());
    }
    Ok(format!("Aid deadlines: {}", lines.join("; ")))
}

fn exec_list_brag_entries(state: &AppState) -> CmdResult<String> {
    let rows: Vec<String> = state.db.with_conn(|conn| {
        let mut stmt = conn.prepare(
            "SELECT title, occurred_at FROM career_brag_entry ORDER BY occurred_at DESC LIMIT 6",
        )?;
        let mut out = Vec::new();
        let mapped = stmt.query_map([], |r| {
            Ok(format!("{} ({})", r.get::<_, String>(0)?, r.get::<_, String>(1)?))
        })?;
        for row in mapped {
            out.push(row?);
        }
        Ok(out)
    })?;
    if rows.is_empty() {
        return Ok("No brag book entries yet.".into());
    }
    Ok(format!("Highlights: {}", rows.join("; ")))
}

fn exec_list_network_contacts(state: &AppState) -> CmdResult<String> {
    let rows: Vec<String> = state.db.with_conn(|conn| {
        let mut stmt = conn.prepare(
            "SELECT name, organization FROM career_network_contact ORDER BY sort_order ASC, name ASC LIMIT 8",
        )?;
        let mut out = Vec::new();
        let mapped = stmt.query_map([], |r| {
            Ok(format!("{} @ {}", r.get::<_, String>(0)?, r.get::<_, String>(1)?))
        })?;
        for row in mapped {
            out.push(row?);
        }
        Ok(out)
    })?;
    if rows.is_empty() {
        return Ok("No network contacts saved.".into());
    }
    Ok(format!("Network: {}", rows.join("; ")))
}

fn exec_assess_registration_readiness(state: &AppState) -> CmdResult<String> {
    let (open_tasks, sections): (i64, i64) = state.db.with_conn(|conn| {
        let open: i64 = conn
            .query_row(
                "SELECT COUNT(*) FROM planner_task WHERE is_complete = 0",
                [],
                |r| r.get(0),
            )
            .unwrap_or(0);
        let sections: i64 = conn
            .query_row(
                "SELECT COUNT(DISTINCT section_title) FROM catalog_degree_requirement",
                [],
                |r| r.get(0),
            )
            .unwrap_or(0);
        Ok((open, sections))
    })?;
    let ready = sections > 0 && open_tasks <= 8;
    Ok(format!(
        "Registration readiness: {} — {} open tasks, {} requirement sections configured.",
        if ready { "likely ready" } else { "needs attention" },
        open_tasks,
        sections
    ))
}

fn exec_get_document_excerpt(state: &AppState, user_msg: &str) -> CmdResult<String> {
    let like = format!("%{}%", user_msg.replace('%', ""));
    let row: Option<(String, String, String)> = state.db.with_conn(|conn| {
        conn.query_row(
            "SELECT title, category, relative_path FROM vault_document
             WHERE is_folder = 0 AND title LIKE ?1
             ORDER BY updated_at DESC LIMIT 1",
            rusqlite::params![like],
            |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)),
        )
        .optional()
        .map_err(Into::into)
    })?;
    let Some((title, category, path)) = row else {
        return Ok("No matching vault document.".into());
    };
    Ok(format!("Document {title} [{category}] at {path}"))
}

pub(crate) fn exec_get_sap_status(state: &AppState) -> CmdResult<String> {
    let (attempted, completed): (f64, f64) = state.db.with_conn(|conn| {
        let attempted: f64 = conn
            .query_row(
                "SELECT COALESCE(SUM(credits), 0) FROM planner_course
                 WHERE status IN ('completed', 'dropped', 'failed', 'transfer')",
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
        Ok((attempted, completed))
    })?;
    let rate = if attempted > 0.0 {
        completed / attempted
    } else {
        1.0
    };
    let threshold = 0.67;
    let status = if attempted == 0.0 {
        "no_history"
    } else if rate < threshold {
        "at_risk"
    } else if rate < threshold + 0.05 {
        "watch"
    } else {
        "good_standing"
    };
    Ok(format!(
        "SAP: {status} — {completed:.0}/{attempted:.0} completed/attempted credits ({:.0}% completion, threshold 67%).",
        rate * 100.0
    ))
}

pub(crate) fn exec_get_full_time_status(state: &AppState, user_msg: &str) -> CmdResult<String> {
    let threshold = 12.0;
    let rows: Vec<(String, f64)> = state.db.with_conn(|conn| {
        let mut stmt = conn.prepare(
            "SELECT COALESCE(s.label, s.season || ' ' || s.year), COALESCE(SUM(c.credits), 0)
             FROM planner_semester s
             LEFT JOIN planner_course c ON c.semester_id = s.id AND c.status != 'dropped'
             GROUP BY s.id
             ORDER BY s.year DESC, s.season DESC
             LIMIT 8",
        )?;
        let mut out = Vec::new();
        let mapped = stmt.query_map([], |r| Ok((r.get::<_, String>(0)?, r.get::<_, f64>(1)?)))?;
        for row in mapped {
            out.push(row?);
        }
        Ok(out)
    })?;
    if rows.is_empty() {
        return Ok("No planner semesters — add a term to check full-time status.".into());
    }
    let needle = user_msg.to_lowercase();
    let pick = rows
        .iter()
        .find(|(label, _)| needle.contains(&label.to_lowercase()))
        .or_else(|| rows.first());
    let Some((label, credits)) = pick else {
        return Ok("Could not resolve semester.".into());
    };
    let meets = *credits >= threshold;
    Ok(format!(
        "Full-time check for {label}: {credits:.1} planned credits (threshold {threshold:.0}) — {}.",
        if meets { "meets full-time" } else { "below full-time" }
    ))
}

fn exec_get_job_resume_match(state: &AppState, user_msg: &str) -> CmdResult<String> {
    let like = format!("%{}%", user_msg.replace('%', ""));
    let app: Option<(String, String, String)> = state.db.with_conn(|conn| {
        conn.query_row(
            "SELECT company, role_title, notes FROM job_application
             WHERE company LIKE ?1 OR role_title LIKE ?1
             ORDER BY updated_at DESC LIMIT 1",
            rusqlite::params![like],
            |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)),
        )
        .optional()
        .map_err(Into::into)
    })?;
    let resume: Option<String> = state.db.with_conn(|conn| {
        conn.query_row(
            "SELECT COALESCE(notes, target_role || ' ' || target_company)
             FROM career_resume_profile ORDER BY updated_at DESC LIMIT 1",
            [],
            |r| r.get(0),
        )
        .optional()
        .map_err(Into::into)
    })?;
    let Some((company, role, notes)) = app else {
        return Ok("Include a company or role to match, or add a job application first.".into());
    };
    let job_text = format!("{role} {company} {notes}");
    let resume_text = resume.unwrap_or_default();
    if resume_text.trim().is_empty() {
        return Ok(format!(
            "No resume profile saved yet — add one in Career → Resume to match against {company}."
        ));
    }
    let (score, _matched, missing) = resume_match_score(&resume_text, &job_text);
    let missing_preview: Vec<_> = missing.into_iter().take(8).collect();
    Ok(format!(
        "Resume match for {company} — {role}: {score}% keyword overlap. Missing keywords: {}.",
        if missing_preview.is_empty() {
            "none".into()
        } else {
            missing_preview.join(", ")
        }
    ))
}

fn exec_get_student_learning_profile(state: &AppState) -> CmdResult<String> {
    let major: String = state.db.with_conn(|conn| {
        Ok(conn
            .query_row(
                "SELECT major FROM profile ORDER BY updated_at DESC LIMIT 1",
                [],
                |r| r.get::<_, String>(0),
            )
            .unwrap_or_default())
    })?;
    let major_prefix = major
        .split_whitespace()
        .next()
        .unwrap_or("")
        .chars()
        .take(3)
        .collect::<String>()
        .to_ascii_uppercase();
    let courses: Vec<String> = state.db.with_conn(|conn| {
        let mut stmt = conn.prepare(
            "SELECT code, title, credits, status FROM planner_course
             ORDER BY code ASC LIMIT 24",
        )?;
        let mut out = Vec::new();
        let rows = stmt.query_map([], |r| {
            Ok((
                r.get::<_, String>(0)?,
                r.get::<_, String>(1)?,
                r.get::<_, f64>(2)?,
                r.get::<_, String>(3)?,
            ))
        })?;
        for row in rows {
            let (code, title, credits, status) = row?;
            out.push(format!("{code} {title} ({credits} cr, {status})"));
        }
        Ok(out)
    })?;
    if courses.is_empty() {
        return Ok("Learning profile empty — add courses to your planner.".into());
    }
    let major_relevant = if major_prefix.is_empty() {
        0
    } else {
        courses
            .iter()
            .filter(|c| c.to_uppercase().contains(&major_prefix))
            .count()
    };
    let eligible = major_relevant >= 2;
    Ok(format!(
        "Learning profile: {} course(s), major \"{major}\", {major_relevant} major-relevant, personalizationEligible={eligible}. {}",
        courses.len(),
        courses.into_iter().take(6).collect::<Vec<_>>().join("; ")
    ))
}

fn exec_explain_sap_policy(state: &AppState) -> CmdResult<String> {
    let stats = exec_get_sap_status(state)?;
    Ok(format!(
        "SAP policy: schools typically require ~67% completion of attempted credits to remain aid-eligible. {stats}"
    ))
}

fn extract_target_credits(msg: &str) -> f64 {
    let re = Regex::new(r"(?i)(\d{1,2})\s*credits?").ok();
    if let Some(re) = re {
        if let Some(caps) = re.captures(msg) {
            if let Some(n) = caps.get(1).and_then(|m| m.as_str().parse::<f64>().ok()) {
                return n.clamp(3.0, 21.0);
            }
        }
    }
    15.0
}

fn exec_draft_semester_plan(state: &AppState, user_msg: &str) -> CmdResult<String> {
    let target = extract_target_credits(user_msg);
    let planned_codes: std::collections::HashSet<String> = state.db.with_conn(|conn| {
        let mut stmt = conn.prepare("SELECT UPPER(code) FROM planner_course")?;
        let mut out = std::collections::HashSet::new();
        let rows = stmt.query_map([], |r| r.get::<_, String>(0))?;
        for row in rows {
            out.insert(row?);
        }
        Ok(out)
    })?;
    let candidates: Vec<String> = state.db.with_conn(|conn| {
        let mut stmt = conn.prepare(
            "SELECT code, title, credits FROM course_catalog
             ORDER BY code ASC LIMIT 120",
        )?;
        let mut out = Vec::new();
        let mut picked = 0.0;
        let rows = stmt.query_map([], |r| {
            Ok((
                r.get::<_, String>(0)?,
                r.get::<_, String>(1)?,
                r.get::<_, f64>(2)?,
            ))
        })?;
        for row in rows {
            let (code, title, credits) = row?;
            if planned_codes.contains(&code.to_ascii_uppercase()) {
                continue;
            }
            if picked + credits > target + 1.0 {
                continue;
            }
            out.push(format!("{code} — {title} ({credits} cr)"));
            picked += credits;
            if picked >= target {
                break;
            }
        }
        Ok(out)
    })?;
    if candidates.is_empty() {
        return Ok(
            "No catalog candidates for a draft plan — ingest catalog courses or adjust your planner."
                .into(),
        );
    }
    Ok(format!(
        "Draft semester plan (~{target:.0} credits, read-only): {}. Confirm adds via planner tools.",
        candidates.join("; ")
    ))
}
