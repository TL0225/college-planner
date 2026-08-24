use crate::commands::CmdResult;
use crate::AppState;
use regex::Regex;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::path::Path;
use tauri::State;
use uuid::Uuid;

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SyllabusAssignmentDto {
    pub title: String,
    pub due_hint: Option<String>,
    pub line: String,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SyllabusExtractResult {
    pub assignments: Vec<SyllabusAssignmentDto>,
    pub course_hint: Option<String>,
    pub raw_line_count: i64,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SyllabusDraftEventDto {
    pub id: String,
    pub title: String,
    pub kind: String,
    pub start_at: Option<String>,
    pub end_at: Option<String>,
    pub location: Option<String>,
    pub due_hint: Option<String>,
    pub included: bool,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SyllabusGradingCategoryDto {
    pub name: String,
    pub weight_percent: Option<f64>,
}

#[derive(Debug, Serialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct SyllabusInstructorDto {
    pub name: Option<String>,
    pub email: Option<String>,
    pub office_hours: Option<String>,
    pub contact: Option<String>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SyllabusSectionDto {
    pub id: String,
    pub label: String,
    pub meeting_days: Option<String>,
    pub meeting_time: Option<String>,
    pub location: Option<String>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SyllabusAnalyzeResult {
    pub events: Vec<SyllabusDraftEventDto>,
    pub grading: Vec<SyllabusGradingCategoryDto>,
    pub instructor: SyllabusInstructorDto,
    pub sections: Vec<SyllabusSectionDto>,
    pub assignments: Vec<SyllabusAssignmentDto>,
    pub course_hint: Option<String>,
    pub course_title: Option<String>,
    pub raw_line_count: i64,
    pub content_hash: String,
    pub warnings: Vec<String>,
    pub extracted_text_preview: Option<String>,
    pub extracted_text: Option<String>,
    pub source_path: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SyllabusExtractInput {
    pub text: String,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SyllabusAnalyzePathInput {
    pub path: String,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SyllabusResolvePdfInput {
    pub vault_doc_id: Option<String>,
    pub path: Option<String>,
}

fn content_hash(text: &str) -> String {
    let mut hasher = Sha256::new();
    hasher.update(text.as_bytes());
    hex::encode(hasher.finalize())
}

fn classify_kind(line: &str) -> &'static str {
    let u = line.to_ascii_lowercase();
    if u.contains("final exam") || u.contains("midterm") || u.contains(" mid-term") || u.contains(" exam ") {
        return "exam";
    }
    if u.contains("quiz") {
        return "quiz";
    }
    if u.contains("reading") {
        return "reading";
    }
    if u.contains("project") {
        return "project";
    }
    if u.contains("lab") {
        return "lab";
    }
    if u.contains("homework") || u.contains(" hw ") || u.starts_with("hw ") {
        return "homework";
    }
    "assignment"
}

fn analyze_lines(lines: &[&str]) -> SyllabusAnalyzeResult {
    let due_re = Regex::new(
        r"(?i)\b(due|deadline|submit by|assignment|homework|exam|quiz|project|reading|lab)\b",
    )
    .expect("due regex");
    let date_re = Regex::new(
        r"(?i)\b(?:(?:jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.?\s+\d{1,2}(?:,?\s+\d{4})?|\d{1,2}/\d{1,2}(?:/\d{2,4})?)\b",
    )
    .expect("date regex");
    let grading_re = Regex::new(
        r"(?i)^(.{2,40}?)\s*[-–:]\s*(\d{1,3})\s*%\s*$",
    )
    .expect("grading regex");
    let instructor_re =
        Regex::new(r"(?i)(?:instructor|professor|prof\.?)\s*:?\s*(.+)$").expect("instructor regex");
    let email_re = Regex::new(r"(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b").expect("email");
    let office_re =
        Regex::new(r"(?i)(?:office hours?)\s*:?\s*(.+)$").expect("office hours regex");
    let section_re = Regex::new(
        r"(?i)(?:section|sec\.?)\s*([A-Z0-9]+)\b.*?(monday|tuesday|wednesday|thursday|friday|saturday|sunday|mon|tue|wed|thu|fri|sat|sun)",
    )
    .expect("section regex");
    let meeting_re = Regex::new(
        r"(?i)\b((?:mon|tue|wed|thu|fri|sat|sun)[a-z]*(?:\s*,?\s*(?:and\s+)?(?:mon|tue|wed|thu|fri|sat|sun)[a-z]*)*)\s+(\d{1,2}:\d{2}\s*(?:am|pm)?(?:\s*[-–]\s*\d{1,2}:\d{2}\s*(?:am|pm)?)?)",
    )
    .expect("meeting regex");

    let mut assignments = Vec::new();
    let mut events = Vec::new();
    let mut grading = Vec::new();
    let mut instructor = SyllabusInstructorDto::default();
    let mut sections = Vec::new();
    let mut warnings = Vec::new();

    for line in lines {
        if let Some(cap) = grading_re.captures(line) {
            let name = cap.get(1).map(|m| m.as_str().trim()).unwrap_or("").to_string();
            let weight = cap
                .get(2)
                .and_then(|m| m.as_str().parse::<f64>().ok());
            if !name.is_empty() {
                grading.push(SyllabusGradingCategoryDto {
                    name,
                    weight_percent: weight,
                });
            }
        }

        if instructor.name.is_none() {
            if let Some(cap) = instructor_re.captures(line) {
                let name = cap.get(1).map(|m| m.as_str().trim()).unwrap_or("").to_string();
                if !name.is_empty() && name.len() < 80 {
                    instructor.name = Some(name);
                }
            }
        }
        if instructor.email.is_none() {
            if let Some(m) = email_re.find(line) {
                instructor.email = Some(m.as_str().to_string());
            }
        }
        if instructor.office_hours.is_none() {
            if let Some(cap) = office_re.captures(line) {
                let oh = cap.get(1).map(|m| m.as_str().trim()).unwrap_or("").to_string();
                if !oh.is_empty() {
                    instructor.office_hours = Some(oh);
                }
            }
        }

        if let Some(cap) = section_re.captures(line) {
            let label = cap
                .get(1)
                .map(|m| format!("Section {}", m.as_str()))
                .unwrap_or_else(|| "Section".to_string());
            sections.push(SyllabusSectionDto {
                id: Uuid::new_v4().to_string(),
                label,
                meeting_days: cap.get(2).map(|m| m.as_str().to_string()),
                meeting_time: None,
                location: None,
            });
        } else if let Some(cap) = meeting_re.captures(line) {
            sections.push(SyllabusSectionDto {
                id: Uuid::new_v4().to_string(),
                label: format!("Meeting {}", sections.len() + 1),
                meeting_days: cap.get(1).map(|m| m.as_str().to_string()),
                meeting_time: cap.get(2).map(|m| m.as_str().to_string()),
                location: None,
            });
        }

        if !due_re.is_match(line) && !date_re.is_match(line) {
            continue;
        }
        if line.len() < 8 || line.len() > 240 {
            continue;
        }
        let due_hint = date_re.find(line).map(|m| m.as_str().to_string());
        let title = line
            .trim_start_matches(|c: char| c.is_ascii_digit() || c == '.' || c == '-' || c == ')')
            .trim()
            .to_string();
        let title = if title.is_empty() {
            line.to_string()
        } else {
            title
        };
        let kind = classify_kind(line);
        assignments.push(SyllabusAssignmentDto {
            title: title.clone(),
            due_hint: due_hint.clone(),
            line: (*line).to_string(),
        });
        events.push(SyllabusDraftEventDto {
            id: Uuid::new_v4().to_string(),
            title,
            kind: kind.to_string(),
            start_at: None,
            end_at: None,
            location: None,
            due_hint,
            included: true,
        });
        if assignments.len() >= 60 {
            break;
        }
    }

    let course_hint = lines.iter().find(|l| {
        let u = l.to_ascii_uppercase();
        u.contains("COURSE") || u.starts_with("CS ") || u.starts_with("MATH ") || u.starts_with("ENG ")
    }).map(|l| (*l).to_string());

    let course_title = lines
        .iter()
        .find(|l| {
            let u = l.to_ascii_uppercase();
            u.contains("SYLLABUS") || u.contains(" — ") || u.contains(" - ")
        })
        .map(|l| (*l).to_string());

    if events.is_empty() {
        warnings.push("No dated events detected — try a PDF with clearer due-date lines.".into());
    }
    if grading.is_empty() {
        warnings.push("No grading breakdown found.".into());
    }

    let joined = lines.join("\n");
    SyllabusAnalyzeResult {
        events,
        grading,
        instructor,
        sections,
        assignments: assignments.clone(),
        course_hint,
        course_title,
        raw_line_count: lines.len() as i64,
        content_hash: content_hash(&joined),
        warnings,
        extracted_text_preview: if joined.len() > 2000 {
            Some(format!("{}…", &joined[..2000]))
        } else if joined.is_empty() {
            None
        } else {
            Some(joined.clone())
        },
        extracted_text: if joined.is_empty() { None } else { Some(joined) },
        source_path: None,
    }
}

fn analyze_text(text: &str) -> SyllabusAnalyzeResult {
    let lines: Vec<&str> = text.lines().map(str::trim).filter(|l| !l.is_empty()).collect();
    analyze_lines(&lines)
}

#[tauri::command]
pub fn syllabus_extract_assignments(input: SyllabusExtractInput) -> CmdResult<SyllabusExtractResult> {
    let analyzed = analyze_text(&input.text);
    Ok(SyllabusExtractResult {
        assignments: analyzed.assignments,
        course_hint: analyzed.course_hint,
        raw_line_count: analyzed.raw_line_count,
    })
}

#[tauri::command]
pub fn syllabus_analyze_text(input: SyllabusExtractInput) -> CmdResult<SyllabusAnalyzeResult> {
    Ok(analyze_text(&input.text))
}

#[tauri::command]
pub fn syllabus_analyze_pdf_path(input: SyllabusAnalyzePathInput) -> CmdResult<SyllabusAnalyzeResult> {
    let bytes = std::fs::read(&input.path)
        .map_err(|e| anyhow::anyhow!("Could not read PDF at {}: {e}", input.path))?;
    let text = pdf_extract::extract_text_from_mem(&bytes).unwrap_or_default();
    let mut result = analyze_text(&text);
    result.source_path = Some(input.path.clone());
    if text.trim().is_empty() {
        result.warnings.push(
            "Scanned PDF — OCR not available; paste text manually.".into(),
        );
    } else if result.raw_line_count == 0 {
        result.warnings.push("PDF parsed but no text lines were found.".into());
    }
    Ok(result)
}

fn resolve_vault_pdf_path(state: &AppState, id: &str) -> Result<Option<String>, anyhow::Error> {
    let row: Option<(String, String)> = state.db.with_conn(|conn| {
        match conn.query_row(
            "SELECT relative_path, mime_type FROM vault_document WHERE id = ?1 AND is_folder = 0",
            rusqlite::params![id],
            |r| Ok((r.get(0)?, r.get(1)?)),
        ) {
            Ok(v) => Ok(Some(v)),
            Err(rusqlite::Error::QueryReturnedNoRows) => Ok(None),
            Err(e) => Err(e.into()),
        }
    })?;
    let Some((rel, mime)) = row else {
        return Ok(None);
    };
    if rel.is_empty() {
        return Ok(None);
    }
    let is_pdf = mime.to_ascii_lowercase().contains("pdf")
        || rel.to_ascii_lowercase().ends_with(".pdf");
    if !is_pdf {
        return Ok(None);
    }
    let abs = state.paths.vault_dir.join(rel);
    if abs.is_file() {
        Ok(Some(abs.display().to_string()))
    } else {
        Ok(None)
    }
}

#[tauri::command]
pub fn syllabus_resolve_pdf_path(
    state: State<'_, AppState>,
    input: SyllabusResolvePdfInput,
) -> CmdResult<Option<String>> {
    if let Some(path) = input.path.filter(|p| !p.trim().is_empty()) {
        let p = Path::new(&path);
        if p.is_file()
            && path.to_ascii_lowercase().ends_with(".pdf")
        {
            return Ok(Some(path));
        }
    }
    if let Some(id) = input.vault_doc_id.filter(|s| !s.trim().is_empty()) {
        return resolve_vault_pdf_path(state.inner(), &id).map_err(Into::into);
    }
    Ok(None)
}
