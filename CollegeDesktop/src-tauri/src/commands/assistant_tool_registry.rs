//! Static assistant tool registry — keyword scoring + optional LLM refinement.

use crate::ai::ChatMessage;
use crate::ai::openai_compat::{self, AiSettings};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum ToolCategory {
    Read,
    Write,
    Nav,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum RoleAffinity {
    Student,
    Career,
    Academic,
}

#[derive(Debug, Clone, Copy)]
pub struct ToolEntry {
    pub name: &'static str,
    pub description: &'static str,
    pub category: ToolCategory,
    pub keywords: &'static [&'static str],
    pub role_affinity: Option<RoleAffinity>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ToolMetadataDto {
    pub name: String,
    pub description: String,
    pub category: String,
    pub keywords: Vec<String>,
    pub role_affinity: Option<String>,
}

const TOOLS: &[ToolEntry] = &[
    // — write / nav —
    ToolEntry {
        name: "create_task",
        description: "Prepare a new calendar task for confirmation",
        category: ToolCategory::Write,
        keywords: &["add task", "create task", "remind me", "new todo", "todo", "deadline"],
        role_affinity: Some(RoleAffinity::Student),
    },
    ToolEntry {
        name: "create_calendar_event",
        description: "Prepare a new calendar event for confirmation",
        category: ToolCategory::Write,
        keywords: &["add event", "create event", "schedule event", "schedule an"],
        role_affinity: Some(RoleAffinity::Student),
    },
    ToolEntry {
        name: "add_course_to_plan",
        description: "Add a course code to the academic planner",
        category: ToolCategory::Write,
        keywords: &["add course", "add to plan", "add to planner", "enroll"],
        role_affinity: Some(RoleAffinity::Academic),
    },
    ToolEntry {
        name: "add_semester",
        description: "Add a new semester to the planner",
        category: ToolCategory::Write,
        keywords: &["add fall", "add spring", "add semester", "add summer", "add winter"],
        role_affinity: Some(RoleAffinity::Academic),
    },
    ToolEntry {
        name: "remove_course_from_plan",
        description: "Remove a course from the planner",
        category: ToolCategory::Write,
        keywords: &["remove course", "drop course", "from plan", "from planner"],
        role_affinity: Some(RoleAffinity::Academic),
    },
    ToolEntry {
        name: "update_task",
        description: "Update an existing task",
        category: ToolCategory::Write,
        keywords: &["update task", "rename task", "change task"],
        role_affinity: Some(RoleAffinity::Student),
    },
    ToolEntry {
        name: "update_calendar_event",
        description: "Update an existing calendar event",
        category: ToolCategory::Write,
        keywords: &["update event", "rename event", "change event", "move event"],
        role_affinity: Some(RoleAffinity::Student),
    },
    ToolEntry {
        name: "delete_task",
        description: "Delete a calendar task",
        category: ToolCategory::Write,
        keywords: &["delete task", "remove task", "delete todo", "cancel task"],
        role_affinity: Some(RoleAffinity::Student),
    },
    ToolEntry {
        name: "delete_calendar_event",
        description: "Delete a calendar event",
        category: ToolCategory::Write,
        keywords: &["delete event", "remove event", "cancel event"],
        role_affinity: Some(RoleAffinity::Student),
    },
    ToolEntry {
        name: "update_job_application_status",
        description: "Move a job application to a new pipeline stage",
        category: ToolCategory::Write,
        keywords: &["mark applied", "mark interview", "move to offer", "move to rejected", "update status"],
        role_affinity: Some(RoleAffinity::Career),
    },
    ToolEntry {
        name: "track_job_application",
        description: "Track a new job application",
        category: ToolCategory::Write,
        keywords: &["track job", "add job", "track application", "apply to"],
        role_affinity: Some(RoleAffinity::Career),
    },
    ToolEntry {
        name: "open_settings_section",
        description: "Navigate to a Settings section",
        category: ToolCategory::Nav,
        keywords: &["open settings", "go to settings", "settings page"],
        role_affinity: None,
    },
    ToolEntry {
        name: "update_app_setting",
        description: "Change an app preference",
        category: ToolCategory::Write,
        keywords: &["set theme", "change theme", "reduce motion", "preference"],
        role_affinity: None,
    },
    ToolEntry {
        name: "save_web_learning",
        description: "Save a note to assistant web memory",
        category: ToolCategory::Write,
        keywords: &["remember", "save to memory", "save this", "web memory"],
        role_affinity: Some(RoleAffinity::Student),
    },
    ToolEntry {
        name: "open_document",
        description: "Open a vault document",
        category: ToolCategory::Nav,
        keywords: &["open document", "show document", "in vault", "view document"],
        role_affinity: None,
    },
    ToolEntry {
        name: "open_resume_builder",
        description: "Open the resume builder",
        category: ToolCategory::Nav,
        keywords: &["open resume", "resume builder", "edit resume"],
        role_affinity: Some(RoleAffinity::Career),
    },
    ToolEntry {
        name: "update_profile",
        description: "Update profile name, major, or email",
        category: ToolCategory::Write,
        keywords: &["change my major", "change my name", "update my email", "update my profile", "update my"],
        role_affinity: Some(RoleAffinity::Student),
    },
    ToolEntry {
        name: "sync_syllabus_deadlines",
        description: "Sync syllabus deadline drafts to the planner",
        category: ToolCategory::Write,
        keywords: &["sync syllabus", "syllabus deadlines to planner", "sync deadlines"],
        role_affinity: Some(RoleAffinity::Academic),
    },
    ToolEntry {
        name: "navigate_to_page",
        description: "Navigate to an app module or page",
        category: ToolCategory::Nav,
        keywords: &["open ", "go to ", "show ", "navigate", "take me to"],
        role_affinity: None,
    },
    // — core read —
    ToolEntry {
        name: "get_audit_summary",
        description: "Summarize degree planner credits and course counts",
        category: ToolCategory::Read,
        keywords: &["credit", "degree", "course", "semester", "planner", "audit", "progress"],
        role_affinity: Some(RoleAffinity::Academic),
    },
    ToolEntry {
        name: "get_gpa",
        description: "Compute GPA from completed graded courses",
        category: ToolCategory::Read,
        keywords: &["gpa", "grade point", "grades", "grade average"],
        role_affinity: Some(RoleAffinity::Academic),
    },
    ToolEntry {
        name: "list_open_tasks",
        description: "List open calendar tasks and deadlines",
        category: ToolCategory::Read,
        keywords: &["task", "deadline", "todo", "due", "assignment"],
        role_affinity: Some(RoleAffinity::Student),
    },
    ToolEntry {
        name: "list_events",
        description: "List upcoming calendar events",
        category: ToolCategory::Read,
        keywords: &["event", "calendar", "schedule", "meeting", "class time"],
        role_affinity: Some(RoleAffinity::Student),
    },
    ToolEntry {
        name: "career_pipeline_metrics",
        description: "Summarize job application pipeline counts",
        category: ToolCategory::Read,
        keywords: &["job", "career", "pipeline", "interview", "application"],
        role_affinity: Some(RoleAffinity::Career),
    },
    ToolEntry {
        name: "finance_dashboard",
        description: "Summarize net worth, accounts, and budgets",
        category: ToolCategory::Read,
        keywords: &["net worth", "budget", "finance", "spending", "transaction", "account"],
        role_affinity: None,
    },
    ToolEntry {
        name: "vault_semantic_search",
        description: "Semantic search across vault documents",
        category: ToolCategory::Read,
        keywords: &["vault", "semantic", "document search", "attachment"],
        role_affinity: None,
    },
    ToolEntry {
        name: "web_search",
        description: "Search the web for current information",
        category: ToolCategory::Read,
        keywords: &["search", "look up", "lookup", "who is", "what is", "latest news", "on the web", "online"],
        role_affinity: None,
    },
    ToolEntry {
        name: "search_catalog_courses",
        description: "Search the course catalog by code or keyword",
        category: ToolCategory::Read,
        keywords: &["catalog", "course code", "class ", "find course"],
        role_affinity: Some(RoleAffinity::Academic),
    },
    ToolEntry {
        name: "get_degree_audit",
        description: "Read degree requirement audit summary",
        category: ToolCategory::Read,
        keywords: &["degree audit", "requirement", "missing", "graduation"],
        role_affinity: Some(RoleAffinity::Academic),
    },
    ToolEntry {
        name: "search_documents",
        description: "Search vault documents by title or category",
        category: ToolCategory::Read,
        keywords: &["document", "syllabus", "pdf", "file"],
        role_affinity: None,
    },
    ToolEntry {
        name: "list_job_applications",
        description: "List tracked job applications",
        category: ToolCategory::Read,
        keywords: &["application", "applied", "interview", "job list"],
        role_affinity: Some(RoleAffinity::Career),
    },
    ToolEntry {
        name: "fetch_web_page",
        description: "Fetch and summarize a web page URL",
        category: ToolCategory::Read,
        keywords: &["http://", "https://", "fetch page", "read this url", "web page"],
        role_affinity: None,
    },
    // — extended read —
    ToolEntry {
        name: "get_student_profile",
        description: "Read saved student profile identity",
        category: ToolCategory::Read,
        keywords: &["profile", "who am i", "my name", "my email", "my major"],
        role_affinity: Some(RoleAffinity::Student),
    },
    ToolEntry {
        name: "get_program_progress",
        description: "Read program and major progress",
        category: ToolCategory::Read,
        keywords: &["program", "progress", "major", "requirement progress"],
        role_affinity: Some(RoleAffinity::Academic),
    },
    ToolEntry {
        name: "get_upcoming_schedule",
        description: "Read combined upcoming schedule",
        category: ToolCategory::Read,
        keywords: &["upcoming", "this week", "schedule", "week ahead"],
        role_affinity: Some(RoleAffinity::Student),
    },
    ToolEntry {
        name: "semantic_catalog_search",
        description: "Semantic search across catalog courses",
        category: ToolCategory::Read,
        keywords: &["semantic", "similar course", "find similar"],
        role_affinity: Some(RoleAffinity::Academic),
    },
    ToolEntry {
        name: "check_prerequisites",
        description: "Check course prerequisites",
        category: ToolCategory::Read,
        keywords: &["prereq", "prerequisite", "prereqs"],
        role_affinity: Some(RoleAffinity::Academic),
    },
    ToolEntry {
        name: "explain_requirements",
        description: "Explain degree requirements",
        category: ToolCategory::Read,
        keywords: &["requirement", "explain", "what do i need"],
        role_affinity: Some(RoleAffinity::Academic),
    },
    ToolEntry {
        name: "list_career_resumes",
        description: "List saved career resumes",
        category: ToolCategory::Read,
        keywords: &["resume", "cv", "resumes"],
        role_affinity: Some(RoleAffinity::Career),
    },
    ToolEntry {
        name: "get_job_application_detail",
        description: "Read details for a job application",
        category: ToolCategory::Read,
        keywords: &["application detail", "job at", "application for"],
        role_affinity: Some(RoleAffinity::Career),
    },
    ToolEntry {
        name: "compute_arithmetic",
        description: "Evaluate a simple arithmetic expression",
        category: ToolCategory::Read,
        keywords: &["calculate", "compute", "+", "*", "math"],
        role_affinity: None,
    },
    ToolEntry {
        name: "get_app_setting",
        description: "Read an app setting value",
        category: ToolCategory::Read,
        keywords: &["setting", "preference", "config"],
        role_affinity: None,
    },
    ToolEntry {
        name: "list_saved_schools",
        description: "List discovery saved schools",
        category: ToolCategory::Read,
        keywords: &["saved school", "discovery", "schools"],
        role_affinity: Some(RoleAffinity::Student),
    },
    ToolEntry {
        name: "list_programs_under_department",
        description: "List academic programs under a department",
        category: ToolCategory::Read,
        keywords: &["department", "program list", "programs in"],
        role_affinity: Some(RoleAffinity::Academic),
    },
    ToolEntry {
        name: "get_aid_deadlines",
        description: "Read financial aid deadlines",
        category: ToolCategory::Read,
        keywords: &["fafsa", "financial aid", "scholarship", "aid deadline"],
        role_affinity: Some(RoleAffinity::Student),
    },
    ToolEntry {
        name: "list_brag_entries",
        description: "List profile highlight entries",
        category: ToolCategory::Read,
        keywords: &["brag", "highlight", "achievement"],
        role_affinity: Some(RoleAffinity::Career),
    },
    ToolEntry {
        name: "list_network_contacts",
        description: "List career network contacts",
        category: ToolCategory::Read,
        keywords: &["network", "contact", "connections"],
        role_affinity: Some(RoleAffinity::Career),
    },
    ToolEntry {
        name: "assess_registration_readiness",
        description: "Assess course registration readiness",
        category: ToolCategory::Read,
        keywords: &["register", "registration", "ready to register"],
        role_affinity: Some(RoleAffinity::Academic),
    },
    ToolEntry {
        name: "get_document_excerpt",
        description: "Read an excerpt from a vault document",
        category: ToolCategory::Read,
        keywords: &["document", "syllabus", "pdf", "excerpt", "read document"],
        role_affinity: None,
    },
    ToolEntry {
        name: "get_sap_status",
        description: "Read satisfactory academic progress status",
        category: ToolCategory::Read,
        keywords: &["sap", "satisfactory academic", "academic standing"],
        role_affinity: Some(RoleAffinity::Academic),
    },
    ToolEntry {
        name: "get_full_time_status",
        description: "Check full-time enrollment status",
        category: ToolCategory::Read,
        keywords: &["full-time", "full time", "enrollment status"],
        role_affinity: Some(RoleAffinity::Academic),
    },
    ToolEntry {
        name: "get_job_resume_match",
        description: "Score resume fit against a job description",
        category: ToolCategory::Read,
        keywords: &["resume match", "match", "fit", "job fit"],
        role_affinity: Some(RoleAffinity::Career),
    },
    ToolEntry {
        name: "get_student_learning_profile",
        description: "Read student learning profile and course history",
        category: ToolCategory::Read,
        keywords: &["learning profile", "course history", "study pattern"],
        role_affinity: Some(RoleAffinity::Academic),
    },
    ToolEntry {
        name: "explain_sap_policy",
        description: "Explain SAP policy rules",
        category: ToolCategory::Read,
        keywords: &["sap policy", "sap explain", "academic policy"],
        role_affinity: Some(RoleAffinity::Academic),
    },
    ToolEntry {
        name: "draft_semester_plan",
        description: "Draft a suggested semester plan",
        category: ToolCategory::Read,
        keywords: &["draft semester", "suggest semester", "next term", "plan next"],
        role_affinity: Some(RoleAffinity::Academic),
    },
    // — parity read —
    ToolEntry {
        name: "draft_weekly_schedule",
        description: "Draft a weekly schedule from calendar data",
        category: ToolCategory::Read,
        keywords: &["weekly schedule", "week plan", "this week plan"],
        role_affinity: Some(RoleAffinity::Student),
    },
    ToolEntry {
        name: "resolve_event_location",
        description: "Resolve location for a calendar event",
        category: ToolCategory::Read,
        keywords: &["where is", "location of", "room", "event location"],
        role_affinity: Some(RoleAffinity::Student),
    },
    ToolEntry {
        name: "screen_aid_eligibility",
        description: "Screen financial aid eligibility",
        category: ToolCategory::Read,
        keywords: &["eligibility", "eligible for aid", "aid eligible"],
        role_affinity: Some(RoleAffinity::Student),
    },
    ToolEntry {
        name: "estimate_aid_range",
        description: "Estimate financial aid range from COA and SAI",
        category: ToolCategory::Read,
        keywords: &["estimate aid", "aid range", "coa", "sai"],
        role_affinity: Some(RoleAffinity::Student),
    },
    ToolEntry {
        name: "extract_aid_document_facts",
        description: "Extract checklist facts from aid documents",
        category: ToolCategory::Read,
        keywords: &["award letter", "aid document", "fafsa doc"],
        role_affinity: Some(RoleAffinity::Student),
    },
    ToolEntry {
        name: "compare_award_letter_to_planner",
        description: "Compare award letter to finance planner",
        category: ToolCategory::Read,
        keywords: &["award letter", "compare award", "financial aid offer"],
        role_affinity: Some(RoleAffinity::Student),
    },
    ToolEntry {
        name: "assess_requirement_risk",
        description: "Assess graduation requirement risk",
        category: ToolCategory::Read,
        keywords: &["requirement risk", "graduation risk", "at risk"],
        role_affinity: Some(RoleAffinity::Academic),
    },
    ToolEntry {
        name: "simulate_course_swap",
        description: "Simulate swapping courses in the planner",
        category: ToolCategory::Read,
        keywords: &["swap course", "swap ", "replace course"],
        role_affinity: Some(RoleAffinity::Academic),
    },
    ToolEntry {
        name: "suggest_courses_for_skill_gaps",
        description: "Suggest catalog courses for skill gaps",
        category: ToolCategory::Read,
        keywords: &["skill gap", "skills", "courses for skills"],
        role_affinity: Some(RoleAffinity::Career),
    },
    ToolEntry {
        name: "assess_registration_workload",
        description: "Assess credit workload for registration",
        category: ToolCategory::Read,
        keywords: &["workload", "credit load", "heavy semester"],
        role_affinity: Some(RoleAffinity::Academic),
    },
    ToolEntry {
        name: "propose_syllabus_deadline_sync",
        description: "List syllabus deadlines available to sync",
        category: ToolCategory::Read,
        keywords: &["syllabus deadline", "syllabus sync", "deadline sync"],
        role_affinity: Some(RoleAffinity::Academic),
    },
];

const ACTION_VERBS: &[&str] = &[
    "add", "create", "delete", "update", "navigate", "open", "remove", "track", "sync", "schedule",
    "set", "change", "mark", "move", "remember", "save", "go to", "show",
];

fn role_matches(affinity: RoleAffinity, role: &str) -> bool {
    match (affinity, role) {
        (RoleAffinity::Academic, "academics" | "academic") => true,
        (RoleAffinity::Career, "career") => true,
        (RoleAffinity::Student, "general" | "student" | "") => true,
        _ => false,
    }
}

fn has_action_verbs(msg: &str) -> bool {
    ACTION_VERBS.iter().any(|v| msg.contains(v))
}

pub fn all_tool_names() -> Vec<&'static str> {
    TOOLS.iter().map(|t| t.name).collect()
}

pub fn tool_metadata(name: &str) -> Option<ToolMetadataDto> {
    TOOLS
        .iter()
        .find(|t| t.name == name)
        .map(|t| ToolMetadataDto {
            name: t.name.to_string(),
            description: t.description.to_string(),
            category: category_label(t.category).to_string(),
            keywords: t.keywords.iter().map(|k| (*k).to_string()).collect(),
            role_affinity: t.role_affinity.map(role_affinity_label).map(str::to_string),
        })
}

pub fn all_tool_metadata() -> Vec<ToolMetadataDto> {
    TOOLS
        .iter()
        .map(|t| ToolMetadataDto {
            name: t.name.to_string(),
            description: t.description.to_string(),
            category: category_label(t.category).to_string(),
            keywords: t.keywords.iter().map(|k| (*k).to_string()).collect(),
            role_affinity: t.role_affinity.map(role_affinity_label).map(str::to_string),
        })
        .collect()
}

fn category_label(category: ToolCategory) -> &'static str {
    match category {
        ToolCategory::Read => "read",
        ToolCategory::Write => "write",
        ToolCategory::Nav => "nav",
    }
}

fn role_affinity_label(affinity: RoleAffinity) -> &'static str {
    match affinity {
        RoleAffinity::Student => "student",
        RoleAffinity::Career => "career",
        RoleAffinity::Academic => "academic",
    }
}

pub fn score_tools_for_message(msg: &str, role: &str, has_attachments: bool) -> Vec<(String, f32)> {
    let q = msg.to_lowercase();
    let action_msg = has_action_verbs(&q);
    let mut scored: Vec<(String, f32)> = Vec::new();

    for tool in TOOLS {
        let mut score = 0.0f32;

        for kw in tool.keywords {
            if q.contains(kw) {
                score += 1.0 + (kw.len() as f32 * 0.05);
            }
        }

        if has_attachments && matches!(tool.name, "vault_semantic_search" | "get_document_excerpt") {
            score += 2.5;
        }

        if let Some(affinity) = tool.role_affinity {
            if role_matches(affinity, role) {
                score += 0.75;
            }
        }

        match tool.category {
            ToolCategory::Read if !action_msg => score += 0.35,
            ToolCategory::Write if action_msg => score += 2.0,
            ToolCategory::Nav if action_msg => score += 1.5,
            _ => {}
        }

        if tool.name == "finance_dashboard" && role == "finance" {
            score += 1.25;
        }
        if tool.name == "get_audit_summary" && role == "academics" && !q.contains("career") {
            score += 0.5;
        }

        if score > 0.0 {
            scored.push((tool.name.to_string(), score));
        }
    }

    scored.sort_by(|a, b| b.1.total_cmp(&a.1));

    if scored.is_empty() {
        scored.push(("get_audit_summary".into(), 0.5));
    }

    scored
}

#[derive(Serialize)]
struct LlmToolCandidate<'a> {
    name: &'a str,
    description: &'a str,
    category: &'static str,
}

/// Ask the configured OpenAI-compatible endpoint to pick tools from top scored candidates.
pub async fn refine_tools_with_llm(
    settings: &AiSettings,
    message: &str,
    role: &str,
    candidates: &[(String, f32)],
) -> Option<Vec<String>> {
    if !settings.endpoint_configured() || candidates.is_empty() {
        return None;
    }

    let tool_json: Vec<LlmToolCandidate> = candidates
        .iter()
        .filter_map(|(name, _)| {
            TOOLS.iter().find(|t| t.name == name.as_str()).map(|t| LlmToolCandidate {
                name: t.name,
                description: t.description,
                category: category_label(t.category),
            })
        })
        .collect();

    if tool_json.is_empty() {
        return None;
    }

    let tools_payload = serde_json::to_string(&tool_json).ok()?;
    let system = "You select assistant tools for a college app. Reply with ONLY a JSON array of tool name strings from the provided list (1-5 tools). No markdown, no explanation.";
    let user = format!(
        "Role: {role}\nMessage: {message}\n\nTools:\n{tools_payload}\n\nJSON array:"
    );

    let messages = vec![
        ChatMessage {
            role: "system".into(),
            content: system.into(),
        },
        ChatMessage {
            role: "user".into(),
            content: user,
        },
    ];

    let content = openai_compat::chat_completion(settings, &messages, 200)
        .await
        .ok()?;
    parse_tool_names_json(&content, candidates)
}

/// Tool refinement via the on-device Gemma LLM (no Ollama required).
pub fn refine_tools_with_local_llm(
    state: &crate::AppState,
    message: &str,
    role: &str,
    candidates: &[(String, f32)],
) -> Option<Vec<String>> {
    if candidates.is_empty() {
        return None;
    }

    let tool_json: Vec<LlmToolCandidate> = candidates
        .iter()
        .filter_map(|(name, _)| {
            TOOLS.iter().find(|t| t.name == name.as_str()).map(|t| LlmToolCandidate {
                name: t.name,
                description: t.description,
                category: category_label(t.category),
            })
        })
        .collect();

    if tool_json.is_empty() {
        return None;
    }

    let tools_payload = serde_json::to_string(&tool_json).ok()?;
    let system = "You select assistant tools for a college app. Reply with ONLY a JSON array of tool name strings from the provided list (1-5 tools). No markdown, no explanation.";
    let user = format!(
        "Role: {role}\nMessage: {message}\n\nTools:\n{tools_payload}\n\nJSON array:"
    );

    let messages = vec![
        ChatMessage {
            role: "system".into(),
            content: system.into(),
        },
        ChatMessage {
            role: "user".into(),
            content: user,
        },
    ];

    let content = state.ai.complete_sync(&messages, 200).ok()?;
    parse_tool_names_json(&content, candidates)
}

fn parse_tool_names_json(content: &str, candidates: &[(String, f32)]) -> Option<Vec<String>> {
    let trimmed = content.trim();
    let json_slice = trimmed
        .strip_prefix("```json")
        .or_else(|| trimmed.strip_prefix("```"))
        .and_then(|s| s.strip_suffix("```"))
        .map(str::trim)
        .unwrap_or(trimmed);

    #[derive(Deserialize)]
    #[serde(untagged)]
    enum NamesPayload {
        List(Vec<String>),
        Wrapped { tools: Vec<String> },
    }

    let parsed: NamesPayload = serde_json::from_str(json_slice).ok()?;
    let names = match parsed {
        NamesPayload::List(v) => v,
        NamesPayload::Wrapped { tools } => tools,
    };

    let allowed: std::collections::HashSet<&str> = candidates.iter().map(|(n, _)| n.as_str()).collect();
    let mut out: Vec<String> = names
        .into_iter()
        .filter(|n| allowed.contains(n.as_str()))
        .collect();
    if out.is_empty() {
        return None;
    }
    out.dedup();
    Some(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn scores_write_tools_for_action_verbs() {
        let scored = score_tools_for_message("add task finish homework", "general", false);
        let create = scored.iter().find(|(n, _)| n == "create_task");
        assert!(create.is_some());
        assert!(create.unwrap().1 > 1.0);
    }

    #[test]
    fn all_tools_have_metadata() {
        assert_eq!(all_tool_names().len(), TOOLS.len());
        for name in all_tool_names() {
            assert!(tool_metadata(name).is_some());
        }
    }
}
