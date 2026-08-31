//! Assistant turn — registry-scored tool planner + read-only tool loop + synthesis.

use crate::ai::{ChatCompletionRequest, ChatMessage};
use crate::commands::academics::{AuditSummary, GpaSummary};
use crate::commands::calendar::{CalendarEventDto, CalendarTaskDto};
use crate::commands::career::PipelineMetrics;
use crate::commands::finance::FinanceDashboardSummary;
use crate::commands::CmdResult;
use crate::AppState;
use regex::Regex;
use serde::{Deserialize, Serialize};
use std::sync::atomic::{AtomicBool, Ordering};
use tauri::{AppHandle, Emitter, State};

static CANCEL_TURN: AtomicBool = AtomicBool::new(false);
static TURN_ACTIVE: AtomicBool = AtomicBool::new(false);

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AssistantTurnMessage {
    pub role: String,
    pub content: String,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AssistantTurnRequest {
    pub messages: Vec<AssistantTurnMessage>,
    pub agent_role: Option<String>,
    pub attachment_ids: Option<Vec<String>>,
    pub web_memory: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AssistantToolTraceEntry {
    pub name: String,
    pub summary: String,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AssistantReplySource {
    pub title: String,
    pub detail: String,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AssistantPendingAction {
    pub kind: String,
    pub title: String,
    pub due_at: Option<String>,
    pub company: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub role_title: Option<String>,
    pub start_at: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub semester_name: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub course_code: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub course_name: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub credits: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub year: Option<i32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub season: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub existing_title: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub application_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub status: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub navigate_module: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub navigate_page: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub setting_key: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub setting_value: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub summary_body: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub profile_name: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub profile_major: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub profile_university: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub profile_email: Option<String>,
}

pub(crate) fn pending_action(kind: &str, title: &str) -> AssistantPendingAction {
    AssistantPendingAction {
        kind: kind.into(),
        title: title.into(),
        due_at: None,
        company: None,
        role_title: None,
        start_at: None,
        semester_name: None,
        course_code: None,
        course_name: None,
        credits: None,
        year: None,
        season: None,
        existing_title: None,
        application_id: None,
        status: None,
        navigate_module: None,
        navigate_page: None,
        setting_key: None,
        setting_value: None,
        summary_body: None,
        profile_name: None,
        profile_major: None,
        profile_university: None,
        profile_email: None,
    }
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AssistantTurnResponse {
    pub content: String,
    pub tool_trace: Vec<AssistantToolTraceEntry>,
    pub sources: Vec<AssistantReplySource>,
    pub pending_action: Option<AssistantPendingAction>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
struct AssistantToolEvent {
    name: String,
    summary: String,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
struct AssistantChunkEvent {
    chunk: String,
    done: bool,
}

fn check_cancelled() -> bool {
    CANCEL_TURN.load(Ordering::SeqCst)
}

fn emit_tool(app: &AppHandle, name: &str, summary: &str) {
    let _ = app.emit(
        "assistant:tool",
        AssistantToolEvent {
            name: name.to_string(),
            summary: summary.to_string(),
        },
    );
}

fn emit_chunk(app: &AppHandle, chunk: &str, done: bool) {
    let _ = app.emit(
        "assistant:chunk",
        AssistantChunkEvent {
            chunk: chunk.to_string(),
            done,
        },
    );
}

fn tool_label(name: &str) -> &'static str {
    if let Some(label) = crate::commands::assistant_write_tools::tool_label(name) {
        return label;
    }
    if let Some(label) = crate::commands::assistant_tools_parity::tool_label(name) {
        return label;
    }
    if let Some(label) = crate::commands::assistant_tools_extended::tool_label(name) {
        return label;
    }
    match name {
        "get_audit_summary" => "Reading planner…",
        "get_gpa" => "Reading GPA…",
        "list_open_tasks" => "Reading tasks…",
        "list_events" => "Reading calendar…",
        "career_pipeline_metrics" => "Reading career pipeline…",
        "finance_dashboard" => "Reading finance…",
        "vault_semantic_search" => "Searching vault…",
        "web_search" => "Searching the web…",
        "search_catalog_courses" => "Searching catalog…",
        "get_degree_audit" => "Reading degree audit…",
        "search_documents" => "Searching documents…",
        "list_job_applications" => "Reading applications…",
        "fetch_web_page" => "Fetching page…",
        "get_sap_status" => "Reading SAP status…",
        "get_full_time_status" => "Checking full-time status…",
        "get_job_resume_match" => "Reading resume match…",
        "get_student_learning_profile" => "Reading learning profile…",
        "explain_sap_policy" => "Explaining SAP policy…",
        "draft_semester_plan" => "Drafting semester plan…",
        "draft_weekly_schedule" => "Drafting weekly schedule…",
        "resolve_event_location" => "Resolving event location…",
        "screen_aid_eligibility" => "Screening aid eligibility…",
        "estimate_aid_range" => "Estimating aid range…",
        "assess_requirement_risk" => "Assessing requirement risk…",
        "propose_syllabus_deadline_sync" => "Reading syllabus deadlines…",
        _ => "Working…",
    }
}

fn load_ai_settings(state: &AppState) -> crate::ai::openai_compat::AiSettings {
    let values = state
        .db
        .with_conn(|conn| {
            let mut stmt = conn.prepare("SELECT key, value FROM app_settings")?;
            let rows = stmt
                .query_map([], |r| Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?)))?
                .collect::<Result<std::collections::HashMap<_, _>, _>>()?;
            Ok(rows)
        })
        .unwrap_or_default();
    crate::ai::openai_compat::AiSettings::from_map(&values)
}

async fn plan_tools(state: &AppState, user_msg: &str, role: &str, has_attachments: bool) -> Vec<String> {
    use crate::commands::assistant_tool_registry::{refine_tools_with_llm, score_tools_for_message};

    let scored = score_tools_for_message(user_msg, role, has_attachments);
    let mut tools: Vec<String> = scored.iter().take(10).map(|(n, _)| n.clone()).collect();

    let settings = load_ai_settings(state);
    if settings.endpoint_configured() {
        let top5: Vec<(String, f32)> = scored.iter().take(5).cloned().collect();
        if let Some(refined) = refine_tools_with_llm(&settings, user_msg, role, &top5).await {
            let mut merged = refined;
            for (name, _) in scored.iter() {
                if merged.len() >= 10 {
                    break;
                }
                if !merged.contains(name) {
                    merged.push(name.clone());
                }
            }
            tools = merged;
        }
    } else if state.ai.local_llm.is_installed() {
        let top5: Vec<(String, f32)> = scored.iter().take(5).cloned().collect();
        if let Some(refined) =
            crate::commands::assistant_tool_registry::refine_tools_with_local_llm(
                state, user_msg, role, &top5,
            )
        {
            let mut merged = refined;
            for (name, _) in scored.iter() {
                if merged.len() >= 10 {
                    break;
                }
                if !merged.contains(name) {
                    merged.push(name.clone());
                }
            }
            tools = merged;
        }
    }

    if tools.is_empty() {
        tools.push("get_audit_summary".into());
    }
    tools.truncate(10);
    tools
}

fn exec_get_audit_summary(state: &AppState) -> CmdResult<String> {
    let summary: AuditSummary = state
        .db
        .with_conn(|conn| {
            crate::commands::academics::query_audit_summary(conn).map_err(Into::into)
        })?;
    Ok(format!(
        "Audit: {} completed credits, {} planned, {} courses across {} semesters.",
        summary.completed_credits, summary.planned_credits, summary.course_count, summary.semester_count
    ))
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

fn exec_get_gpa(state: &AppState) -> CmdResult<String> {
    let gpa: GpaSummary = state.db.with_conn(|conn| {
        let mut stmt = conn.prepare(
            "SELECT credits, grade FROM planner_course
             WHERE status = 'completed' AND grade IS NOT NULL AND TRIM(grade) != ''",
        )?;
        let rows = stmt.query_map([], |r| Ok((r.get::<_, f64>(0)?, r.get::<_, String>(1)?)))?;
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
        let gpa = if credits > 0.0 { Some(points / credits) } else { None };
        Ok(GpaSummary {
            gpa,
            graded_credits: credits,
            graded_courses: count,
        })
    })?;
    match gpa.gpa {
        Some(v) => Ok(format!(
            "GPA {:.2} across {} graded courses ({} credits).",
            v, gpa.graded_courses, gpa.graded_credits
        )),
        None => Ok("No graded completed courses yet.".into()),
    }
}

fn exec_list_open_tasks(state: &AppState) -> CmdResult<String> {
    let tasks: Vec<CalendarTaskDto> = state.db.with_conn(|conn| {
        let mut stmt = conn.prepare(
            "SELECT id, title, due_at, is_complete FROM planner_task
             WHERE is_complete = 0
             ORDER BY due_at IS NULL, due_at ASC LIMIT 12",
        )?;
        let rows = stmt
            .query_map([], |r| {
                Ok(CalendarTaskDto {
                    id: r.get(0)?,
                    title: r.get(1)?,
                    due_at: r.get(2)?,
                    is_complete: r.get::<_, i64>(3)? != 0,
                })
            })?
            .collect::<Result<Vec<_>, _>>()?;
        Ok(rows)
    })?;
    if tasks.is_empty() {
        return Ok("No open tasks.".into());
    }
    let lines: Vec<String> = tasks
        .iter()
        .map(|t| {
            if let Some(due) = &t.due_at {
                format!("{} (due {})", t.title, due)
            } else {
                t.title.clone()
            }
        })
        .collect();
    Ok(format!("Open tasks ({}): {}", lines.len(), lines.join("; ")))
}

fn exec_list_events(state: &AppState) -> CmdResult<String> {
    let events: Vec<CalendarEventDto> = state.db.with_conn(|conn| {
        let mut stmt = conn.prepare(
            "SELECT id, title, start_at, end_at, all_day, location, notes, provider, color, recurrence, source_id
             FROM calendar_event ORDER BY start_at ASC LIMIT 8",
        )?;
        let rows = stmt
            .query_map([], |r| {
                Ok(CalendarEventDto {
                    id: r.get(0)?,
                    title: r.get(1)?,
                    start_at: r.get(2)?,
                    end_at: r.get(3)?,
                    all_day: r.get::<_, i64>(4)? != 0,
                    location: r.get(5)?,
                    notes: r.get(6)?,
                    provider: r.get(7)?,
                    color: r.get(8)?,
                    recurrence: r.get(9)?,
                    source_id: r.get(10)?,
                })
            })?
            .collect::<Result<Vec<_>, _>>()?;
        Ok(rows)
    })?;
    if events.is_empty() {
        return Ok("No upcoming events.".into());
    }
    let lines: Vec<String> = events
        .iter()
        .map(|e| format!("{} @ {}", e.title, e.start_at))
        .collect();
    Ok(format!("Upcoming events: {}", lines.join("; ")))
}

fn exec_career_pipeline(state: &AppState) -> CmdResult<String> {
    let metrics: PipelineMetrics = state.db.with_conn(|conn| {
        let count = |status: &str| -> i64 {
            conn.query_row(
                "SELECT COUNT(*) FROM job_application WHERE status = ?1",
                [status],
                |r| r.get(0),
            )
            .unwrap_or(0)
        };
        let total: i64 = conn
            .query_row("SELECT COUNT(*) FROM job_application", [], |r| r.get(0))
            .unwrap_or(0);
        Ok(PipelineMetrics {
            interested: count("interested"),
            applied: count("applied"),
            interviewing: count("interviewing"),
            offer: count("offer"),
            rejected: count("rejected"),
            accepted: count("accepted"),
            total,
        })
    })?;
    Ok(format!(
        "Career pipeline: {} total — interested {}, applied {}, interviewing {}, offer {}.",
        metrics.total, metrics.interested, metrics.applied, metrics.interviewing, metrics.offer
    ))
}

fn exec_finance_dashboard(state: &AppState) -> CmdResult<String> {
    let summary: FinanceDashboardSummary = state.db.with_conn(|conn| {
        let account_balance_total: f64 = conn
            .query_row("SELECT COALESCE(SUM(balance), 0) FROM finance_account", [], |r| {
                r.get(0)
            })
            .unwrap_or(0.0);
        let holdings_value: f64 = conn
            .query_row(
                "SELECT COALESCE(SUM(quantity * price_per_unit), 0) FROM finance_holding",
                [],
                |r| r.get(0),
            )
            .unwrap_or(0.0);
        let net_worth = account_balance_total + holdings_value;
        let account_count: i64 = conn
            .query_row("SELECT COUNT(*) FROM finance_account", [], |r| r.get(0))
            .unwrap_or(0);
        let transaction_count: i64 = conn
            .query_row("SELECT COUNT(*) FROM finance_transaction", [], |r| r.get(0))
            .unwrap_or(0);
        let budget_count: i64 = conn
            .query_row("SELECT COUNT(*) FROM finance_budget", [], |r| r.get(0))
            .unwrap_or(0);
        Ok(FinanceDashboardSummary {
            net_worth,
            account_balance_total,
            holdings_value,
            account_count,
            transaction_count,
            budget_count,
        })
    })?;
    Ok(format!(
        "Finance: net worth ${:.2}, {} accounts, {} transactions, {} budgets.",
        summary.net_worth, summary.account_count, summary.transaction_count, summary.budget_count
    ))
}

fn cosine(a: &[f32], b: &[f32]) -> f32 {
    let n = a.len().min(b.len());
    if n == 0 {
        return 0.0;
    }
    let mut dot = 0.0f32;
    let mut na = 0.0f32;
    let mut nb = 0.0f32;
    for i in 0..n {
        dot += a[i] * b[i];
        na += a[i] * a[i];
        nb += b[i] * b[i];
    }
    if na == 0.0 || nb == 0.0 {
        return 0.0;
    }
    dot / (na.sqrt() * nb.sqrt())
}

fn exec_vault_semantic_search(state: &AppState, query: &str) -> CmdResult<String> {
    let q = query.trim();
    if q.is_empty() {
        return Ok("Vault search skipped (empty query).".into());
    }
    let docs: Vec<(String, String, String, String)> = state.db.with_conn(|conn| {
        let mut stmt = conn.prepare(
            "SELECT id, category, title, mime_type FROM vault_document
             ORDER BY updated_at DESC LIMIT 400",
        )?;
        let rows = stmt
            .query_map([], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?)))?
            .collect::<Result<Vec<_>, _>>()?;
        Ok(rows)
    })?;
    if docs.is_empty() {
        return Ok("Vault is empty.".into());
    }
    let mut texts = vec![q.to_string()];
    for (_, category, title, mime) in &docs {
        texts.push(format!("{category} {title} {mime}"));
    }
    let embeds = state.ai.embed(&texts)?;
    let query_vec = embeds.first().cloned().unwrap_or_default();
    let mut scored: Vec<(f32, String)> = docs
        .into_iter()
        .enumerate()
        .filter_map(|(i, (_, category, title, _))| {
            let vec = embeds.get(i + 1)?;
            Some((cosine(&query_vec, vec), format!("{title} [{category}]")))
        })
        .collect();
    scored.sort_by(|a, b| b.0.total_cmp(&a.0));
    scored.truncate(6);
    if scored.is_empty() {
        return Ok("No vault matches.".into());
    }
    let hits: Vec<String> = scored.into_iter().map(|(_, t)| t).collect();
    Ok(format!("Vault matches: {}", hits.join("; ")))
}

fn exec_web_search(query: &str) -> CmdResult<String> {
    let q = query.trim();
    if q.is_empty() {
        return Ok("No search query provided.".into());
    }
    #[derive(Deserialize)]
    struct DdgResponse {
        #[serde(rename = "AbstractText")]
        abstract_text: Option<String>,
        #[serde(rename = "Heading")]
        heading: Option<String>,
        #[serde(rename = "RelatedTopics")]
        related_topics: Option<Vec<DdgTopic>>,
    }
    #[derive(Deserialize)]
    struct DdgTopic {
        #[serde(rename = "Text")]
        text: Option<String>,
    }
    let url = format!(
        "https://api.duckduckgo.com/?q={}&format=json&no_html=1&skip_disambig=1",
        urlencoding::encode(q)
    );
    let body: DdgResponse = reqwest::blocking::Client::builder()
        .timeout(std::time::Duration::from_secs(8))
        .build()
        .map_err(|e| crate::commands::CommandError {
            message: e.to_string(),
        })?
        .get(&url)
        .header("User-Agent", "College-Tauri/1.0")
        .send()
        .map_err(|e| crate::commands::CommandError {
            message: format!("web search failed: {e}"),
        })?
        .json()
        .map_err(|e| crate::commands::CommandError {
            message: format!("web search parse failed: {e}"),
        })?;
    let mut parts = Vec::new();
    if let Some(h) = body.heading.filter(|s| !s.is_empty()) {
        parts.push(h);
    }
    if let Some(t) = body.abstract_text.filter(|s| !s.is_empty()) {
        parts.push(t);
    }
    if let Some(topics) = body.related_topics {
        for topic in topics.into_iter().take(4) {
            if let Some(t) = topic.text.filter(|s| !s.is_empty()) {
                parts.push(t);
            }
        }
    }
    if parts.is_empty() {
        return Ok(format!("No instant answers for \"{q}\". Try rephrasing or be more specific."));
    }
    Ok(format!("Web search: {}", parts.join(" · ")))
}

fn exec_search_catalog_courses(state: &AppState, query: &str) -> CmdResult<String> {
    let q = query.trim();
    if q.is_empty() {
        return Ok("Provide a course code or keyword to search.".into());
    }
    let like = format!("%{}%", q.replace('%', ""));
    let hits: Vec<String> = state.db.with_conn(|conn| {
        let mut stmt = conn.prepare(
            "SELECT code, title FROM course_catalog
             WHERE code LIKE ?1 OR title LIKE ?1
             ORDER BY code ASC LIMIT 12",
        )?;
        let mut hits = Vec::new();
        let rows = stmt.query_map(rusqlite::params![like], |r| {
            let code: String = r.get(0)?;
            let title: String = r.get(1)?;
            Ok(format!("{code} — {title}"))
        })?;
        for row in rows {
            hits.push(row?);
        }
        Ok(hits)
    })?;
    if hits.is_empty() {
        return Ok(format!("No catalog matches for \"{q}\"."));
    }
    Ok(format!("Catalog matches: {}", hits.join("; ")))
}

fn exec_get_degree_audit(state: &AppState) -> CmdResult<String> {
    let summary = exec_get_audit_summary(state)?;
    Ok(format!("Requirement audit: {summary}"))
}

fn exec_search_documents(state: &AppState, query: &str) -> CmdResult<String> {
    let q = query.trim();
    if q.is_empty() {
        return Ok("Provide a document search term.".into());
    }
    let like = format!("%{}%", q.replace('%', ""));
    let hits: Vec<String> = state.db.with_conn(|conn| {
        let mut stmt = conn.prepare(
            "SELECT title, category FROM vault_document
             WHERE is_folder = 0 AND (title LIKE ?1 OR category LIKE ?1)
             ORDER BY updated_at DESC LIMIT 10",
        )?;
        let mut hits = Vec::new();
        let rows = stmt.query_map(rusqlite::params![like], |r| {
            let title: String = r.get(0)?;
            let category: String = r.get(1)?;
            Ok(format!("{title} [{category}]"))
        })?;
        for row in rows {
            hits.push(row?);
        }
        Ok(hits)
    })?;
    if hits.is_empty() {
        return Ok(format!("No documents matching \"{q}\"."));
    }
    Ok(format!("Documents: {}", hits.join("; ")))
}

fn exec_list_job_applications(state: &AppState) -> CmdResult<String> {
    let rows: Vec<String> = state.db.with_conn(|conn| {
        let mut stmt = conn.prepare(
            "SELECT company, role_title, status FROM job_application
             ORDER BY updated_at DESC LIMIT 10",
        )?;
        let mut rows = Vec::new();
        let mapped = stmt.query_map([], |r| {
            let company: String = r.get(0)?;
            let role: String = r.get(1)?;
            let status: String = r.get(2)?;
            Ok(format!("{company} — {role} ({status})"))
        })?;
        for row in mapped {
            rows.push(row?);
        }
        Ok(rows)
    })?;
    if rows.is_empty() {
        return Ok("No job applications tracked yet.".into());
    }
    Ok(format!("Applications: {}", rows.join("; ")))
}

fn extract_url(text: &str) -> Option<String> {
    for token in text.split_whitespace() {
        let t = token.trim_matches(|c: char| !c.is_ascii_alphanumeric() && c != ':' && c != '/' && c != '.');
        if t.starts_with("http://") || t.starts_with("https://") {
            return Some(t.to_string());
        }
    }
    None
}

fn strip_html(html: &str) -> String {
    let mut out = String::new();
    let mut in_tag = false;
    for ch in html.chars().take(50_000) {
        match ch {
            '<' => in_tag = true,
            '>' => in_tag = false,
            _ if !in_tag => {
                out.push(ch);
            }
            _ => {}
        }
    }
    out.split_whitespace().collect::<Vec<_>>().join(" ")
}

fn exec_fetch_web_page(user_msg: &str) -> CmdResult<String> {
    let url = extract_url(user_msg).ok_or_else(|| crate::commands::CommandError {
        message: "No URL found in message.".into(),
    })?;
    let body = reqwest::blocking::Client::builder()
        .timeout(std::time::Duration::from_secs(12))
        .build()
        .map_err(|e| crate::commands::CommandError {
            message: e.to_string(),
        })?
        .get(&url)
        .header("User-Agent", "College-Tauri/1.0")
        .send()
        .map_err(|e| crate::commands::CommandError {
            message: format!("fetch failed: {e}"),
        })?
        .text()
        .map_err(|e| crate::commands::CommandError {
            message: format!("read failed: {e}"),
        })?;
    let text = strip_html(&body);
    let excerpt: String = text.chars().take(1200).collect();
    Ok(format!("Page excerpt from {url}: {excerpt}"))
}

fn run_tool(
    app: &AppHandle,
    state: &AppState,
    name: &str,
    user_msg: &str,
) -> CmdResult<(String, Option<AssistantPendingAction>)> {
    if let Some(result) =
        crate::commands::assistant_write_tools::run_write_tool(app, state, name, user_msg)
    {
        let outcome = result?;
        return Ok((outcome.summary, outcome.pending));
    }
    if let Some(result) =
        crate::commands::assistant_tools_extended::run_extended_tool(state, name, user_msg)
    {
        let summary = result?;
        return Ok((summary, None));
    }
    if let Some(result) = crate::commands::assistant_tools_parity::run_parity_tool(state, name, user_msg) {
        let summary = result?;
        return Ok((summary, None));
    }
    let summary = match name {
        "get_audit_summary" => exec_get_audit_summary(state)?,
        "get_gpa" => exec_get_gpa(state)?,
        "list_open_tasks" => exec_list_open_tasks(state)?,
        "list_events" => exec_list_events(state)?,
        "career_pipeline_metrics" => exec_career_pipeline(state)?,
        "finance_dashboard" => exec_finance_dashboard(state)?,
        "vault_semantic_search" => exec_vault_semantic_search(state, user_msg)?,
        "web_search" => exec_web_search(user_msg)?,
        "search_catalog_courses" => exec_search_catalog_courses(state, user_msg)?,
        "get_degree_audit" => exec_get_degree_audit(state)?,
        "search_documents" => exec_search_documents(state, user_msg)?,
        "list_job_applications" => exec_list_job_applications(state)?,
        "fetch_web_page" => exec_fetch_web_page(user_msg)?,
        _ => format!("Unknown tool: {name}"),
    };
    Ok((summary, None))
}

fn attachment_context(state: &AppState, ids: &[String]) -> CmdResult<String> {
    if ids.is_empty() {
        return Ok(String::new());
    }
    let placeholders = ids.iter().map(|_| "?").collect::<Vec<_>>().join(", ");
    let sql = format!(
        "SELECT title, category FROM vault_document WHERE id IN ({placeholders})"
    );
    let titles: Vec<String> = state.db.with_conn(|conn| {
        let mut stmt = conn.prepare(&sql)?;
        let params: Vec<&dyn rusqlite::ToSql> =
            ids.iter().map(|id| id as &dyn rusqlite::ToSql).collect();
        let rows = stmt.query_map(rusqlite::params_from_iter(params.iter()), |r| {
            let title: String = r.get(0)?;
            let category: String = r.get(1)?;
            Ok(format!("{title} [{category}]"))
        })?;
        rows.collect::<Result<Vec<_>, _>>().map_err(Into::into)
    })?;
    if titles.is_empty() {
        return Ok(String::new());
    }
    Ok(format!("Attached vault documents: {}", titles.join("; ")))
}

fn role_hint(role: &str) -> &'static str {
    match role {
        "academics" => {
            "Agent role: academics. Prioritize degree progress, credits, GPA, and courses."
        }
        "career" => "Agent role: career. Prioritize applications, pipeline, and interviews.",
        "finance" => "Agent role: finance. Prioritize net worth, accounts, and budgets.",
        _ => "Agent role: general. Answer across academics, calendar, career, and finance.",
    }
}

fn detect_create_task(msg: &str) -> Option<AssistantPendingAction> {
    let patterns = [
        r"(?i)^create task[:\s]+(.+)$",
        r"(?i)^add task[:\s]+(.+)$",
        r"(?i)^remind me to (.+)$",
        r"(?i)^new todo[:\s]+(.+)$",
        r"(?i)^add (?:a )?todo[:\s]+(.+)$",
    ];
    for pat in patterns {
        if let Ok(re) = Regex::new(pat) {
            if let Some(caps) = re.captures(msg.trim()) {
                let title = caps.get(1)?.as_str().trim();
                if !title.is_empty() {
                    return Some(pending_action("createTask", title));
                }
            }
        }
    }
    None
}

fn detect_create_event(msg: &str) -> Option<AssistantPendingAction> {
    let patterns = [
        r"(?i)^add event[:\s]+(.+)$",
        r"(?i)^create event[:\s]+(.+)$",
        r"(?i)^schedule an event[:\s]+(.+)$",
        r"(?i)^schedule[:\s]+(.+)$",
    ];
    for pat in patterns {
        if let Ok(re) = Regex::new(pat) {
            if let Some(caps) = re.captures(msg.trim()) {
                let title = caps.get(1)?.as_str().trim();
                if !title.is_empty() {
                    return Some(pending_action("createEvent", title));
                }
            }
        }
    }
    None
}

pub(crate) fn create_application_action(role_title: &str, company: &str) -> AssistantPendingAction {
    let role = role_title.trim();
    let company = company.trim();
    let display_role = if role.is_empty() { "Open role" } else { role };
    let mut action = pending_action("createApplication", display_role);
    action.company = Some(company.to_string());
    action.role_title = Some(display_role.to_string());
    action
}

pub(crate) fn detect_create_application(msg: &str) -> Option<AssistantPendingAction> {
    let role_company_patterns = [
        r"(?i)^track (?:a )?job (.+?) at (.+)$",
        r"(?i)^add job (.+?) at (.+)$",
        r"(?i)^track application (?:for )?(.+?) at (.+)$",
    ];
    for pat in role_company_patterns {
        if let Ok(re) = Regex::new(pat) {
            if let Some(caps) = re.captures(msg.trim()) {
                let role = caps.get(1)?.as_str().trim();
                let company = caps.get(2)?.as_str().trim();
                if !role.is_empty() && !company.is_empty() {
                    return Some(create_application_action(role, company));
                }
            }
        }
    }
    let company_only_patterns = [
        r"(?i)^track job at (.+)$",
        r"(?i)^track application at (.+)$",
        r"(?i)^add job at (.+)$",
        r"(?i)^track (?:a )?job (?:at|for) (.+)$",
    ];
    for pat in company_only_patterns {
        if let Ok(re) = Regex::new(pat) {
            if let Some(caps) = re.captures(msg.trim()) {
                let company = caps.get(1)?.as_str().trim();
                if !company.is_empty() {
                    return Some(create_application_action("Open role", company));
                }
            }
        }
    }
    None
}

fn detect_pending_action(msg: &str) -> Option<AssistantPendingAction> {
    detect_create_task(msg)
        .or_else(|| detect_create_event(msg))
        .or_else(|| detect_create_application(msg))
}

fn chunk_text(text: &str, size: usize) -> Vec<String> {
    if text.is_empty() {
        return vec![];
    }
    text.chars()
        .collect::<Vec<_>>()
        .chunks(size)
        .map(|c| c.iter().collect())
        .collect()
}

#[tauri::command]
pub async fn assistant_turn(
    app: AppHandle,
    state: State<'_, AppState>,
    request: AssistantTurnRequest,
) -> CmdResult<AssistantTurnResponse> {
    CANCEL_TURN.store(false, Ordering::SeqCst);
    TURN_ACTIVE.store(true, Ordering::SeqCst);

    let finish = || {
        TURN_ACTIVE.store(false, Ordering::SeqCst);
    };

    let role = request.agent_role.as_deref().unwrap_or("general");
    let attachment_ids = request.attachment_ids.unwrap_or_default();
    let web_memory = request.web_memory.unwrap_or_default();

    let user_msg = request
        .messages
        .iter()
        .rev()
        .find(|m| m.role == "user")
        .map(|m| m.content.clone())
        .unwrap_or_default();

    if check_cancelled() {
        finish();
        return Err(crate::commands::CommandError {
            message: "Turn cancelled".into(),
        });
    }

    let mut pending_action = detect_pending_action(&user_msg);
    let planned = plan_tools(&state, &user_msg, role, !attachment_ids.is_empty()).await;
    let mut tool_trace: Vec<AssistantToolTraceEntry> = Vec::new();
    let mut tool_results: Vec<String> = Vec::new();

    for name in planned {
        if check_cancelled() {
            finish();
            return Err(crate::commands::CommandError {
                message: "Turn cancelled".into(),
            });
        }
        let label = tool_label(&name);
        emit_tool(&app, &name, label);
        let (summary, write_pending) = run_tool(&app, &state, &name, &user_msg)?;
        if write_pending.is_some() {
            pending_action = write_pending;
        }
        tool_trace.push(AssistantToolTraceEntry {
            name: name.clone(),
            summary: summary.clone(),
        });
        emit_tool(&app, &name, &summary);
        tool_results.push(format!("[{name}] {summary}"));
    }

    if check_cancelled() {
        finish();
        return Err(crate::commands::CommandError {
            message: "Turn cancelled".into(),
        });
    }

    let attachment_block = attachment_context(&state, &attachment_ids)?;
    let mut system_parts = vec![
        role_hint(role).to_string(),
        "You are College Assistant. Ground answers in the tool results below. Be concise and helpful."
            .to_string(),
    ];
    if !web_memory.trim().is_empty() {
        system_parts.push(format!("Web memory:\n{}", web_memory.trim()));
    }
    if !attachment_block.is_empty() {
        system_parts.push(attachment_block);
    }
    if !tool_results.is_empty() {
        system_parts.push(format!("Tool results:\n{}", tool_results.join("\n")));
    }

    let mut chat_messages: Vec<ChatMessage> = vec![ChatMessage {
        role: "system".into(),
        content: system_parts.join("\n\n"),
    }];
    for m in &request.messages {
        chat_messages.push(ChatMessage {
            role: m.role.clone(),
            content: m.content.clone(),
        });
    }

    let chat_req = ChatCompletionRequest {
        messages: chat_messages,
        max_tokens: Some(768),
    };

    let app_emit = app.clone();
    let chat_res = state
        .ai
        .chat_stream_async(chat_req, move |delta| {
            if !check_cancelled() {
                emit_chunk(&app_emit, delta, false);
            }
        })
        .await
        .map_err(|e| {
            finish();
            crate::commands::CommandError {
                message: e.to_string(),
            }
        })?;

    if check_cancelled() {
        finish();
        return Err(crate::commands::CommandError {
            message: "Turn cancelled".into(),
        });
    }

    emit_chunk(&app, "", true);

    finish();
    Ok(AssistantTurnResponse {
        content: chat_res.content,
        tool_trace,
        sources: vec![],
        pending_action,
    })
}

#[tauri::command]
pub fn assistant_list_tools() -> CmdResult<Vec<crate::commands::assistant_tool_registry::ToolMetadataDto>> {
    Ok(crate::commands::assistant_tool_registry::all_tool_metadata())
}

#[tauri::command]
pub fn assistant_cancel_turn() -> CmdResult<bool> {
    if TURN_ACTIVE.load(Ordering::SeqCst) {
        CANCEL_TURN.store(true, Ordering::SeqCst);
        Ok(true)
    } else {
        Ok(false)
    }
}
