use crate::commands::CmdResult;
use crate::db::DbChangeEvent;
use crate::AppState;
use regex::Regex;
use scraper::{Html, Selector};
use serde::{Deserialize, Serialize};
use tauri::{AppHandle, Emitter, State};
use uuid::Uuid;

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct TransferEquivalencyDto {
    pub id: String,
    pub source_school: String,
    pub source_code: String,
    pub target_code: String,
    pub credits: Option<f64>,
    pub notes: String,
    pub proof_document_id: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UpsertTransferInput {
    pub source_school: String,
    pub source_code: String,
    pub target_code: String,
    pub credits: Option<f64>,
    pub notes: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ImportTransferRow {
    pub source_school: String,
    pub source_code: String,
    pub target_code: String,
    pub credits: Option<f64>,
    pub notes: Option<String>,
}

fn upsert_equivalency_row(
    conn: &rusqlite::Connection,
    input: &UpsertTransferInput,
) -> rusqlite::Result<String> {
    let id = Uuid::new_v4().to_string();
    let dedupe = format!(
        "{}|{}|{}",
        input.source_school.trim().to_ascii_lowercase(),
        input.source_code.trim().to_ascii_uppercase(),
        input.target_code.trim().to_ascii_uppercase()
    );
    conn.execute(
        "INSERT INTO transfer_equivalency
         (id, source_school, source_code, target_code, credits, notes, dedupe_key, proof_document_id)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, NULL)
         ON CONFLICT(dedupe_key) DO UPDATE SET
           credits = excluded.credits,
           notes = excluded.notes",
        rusqlite::params![
            id,
            input.source_school.trim(),
            input.source_code.trim(),
            input.target_code.trim(),
            input.credits,
            input.notes.as_deref().unwrap_or(""),
            dedupe
        ],
    )?;
    conn.query_row(
        "SELECT id FROM transfer_equivalency WHERE dedupe_key = ?1",
        rusqlite::params![dedupe],
        |r| r.get(0),
    )
}

fn bump_transfer(app: &AppHandle, state: &AppState) -> CmdResult<()> {
    let rev = state.db.bump_revision("transfer")?;
    let _ = app.emit(
        "db:change",
        DbChangeEvent {
            domain: "transfer".to_string(),
            revision: rev,
        },
    );
    Ok(())
}

#[tauri::command]
pub fn transfer_list_equivalencies(
    state: State<'_, AppState>,
) -> CmdResult<Vec<TransferEquivalencyDto>> {
    state
        .db
        .with_conn(|conn| {
            let mut stmt = conn.prepare(
                "SELECT id, source_school, source_code, target_code, credits, notes, proof_document_id
                 FROM transfer_equivalency
                 ORDER BY source_school ASC, source_code ASC
                 LIMIT 400",
            )?;
            let rows = stmt
                .query_map([], |r| {
                    Ok(TransferEquivalencyDto {
                        id: r.get(0)?,
                        source_school: r.get(1)?,
                        source_code: r.get(2)?,
                        target_code: r.get(3)?,
                        credits: r.get(4)?,
                        notes: r.get(5)?,
                        proof_document_id: r.get(6)?,
                    })
                })?
                .collect::<Result<Vec<_>, _>>()?;
            Ok(rows)
        })
        .map_err(Into::into)
}

#[tauri::command]
pub fn transfer_upsert_equivalency(
    app: AppHandle,
    state: State<'_, AppState>,
    input: UpsertTransferInput,
) -> CmdResult<String> {
    let resolved = state
        .db
        .with_conn(|conn| Ok(upsert_equivalency_row(conn, &input)?))?;
    bump_transfer(&app, &state)?;
    Ok(resolved)
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ImportTransferResult {
    pub imported: i64,
    pub skipped: i64,
}

#[tauri::command]
pub fn transfer_import_equivalencies(
    app: AppHandle,
    state: State<'_, AppState>,
    rows: Vec<ImportTransferRow>,
) -> CmdResult<ImportTransferResult> {
    let result = state
        .db
        .with_conn(|conn| Ok(import_equivalency_rows(conn, &rows)?))?;
    bump_transfer(&app, &state)?;
    Ok(result)
}

fn import_equivalency_rows(
    conn: &rusqlite::Connection,
    rows: &[ImportTransferRow],
) -> rusqlite::Result<ImportTransferResult> {
    let mut imported = 0i64;
    let mut skipped = 0i64;
    for row in rows {
        let source_school = row.source_school.trim();
        let source_code = row.source_code.trim();
        let target_code = row.target_code.trim();
        if source_school.is_empty() || source_code.is_empty() || target_code.is_empty() {
            skipped += 1;
            continue;
        }
        let input = UpsertTransferInput {
            source_school: source_school.to_string(),
            source_code: source_code.to_string(),
            target_code: target_code.to_string(),
            credits: row.credits,
            notes: row.notes.clone(),
        };
        upsert_equivalency_row(conn, &input)?;
        imported += 1;
    }
    Ok(ImportTransferResult { imported, skipped })
}

#[tauri::command]
pub fn transfer_delete_equivalency(
    app: AppHandle,
    state: State<'_, AppState>,
    id: String,
) -> CmdResult<()> {
    state.db.with_conn(|conn| {
        conn.execute(
            "DELETE FROM transfer_equivalency WHERE id = ?1",
            rusqlite::params![id],
        )?;
        Ok(())
    })?;
    bump_transfer(&app, &state)?;
    Ok(())
}

#[tauri::command]
pub fn transfer_link_proof_document(
    app: AppHandle,
    state: State<'_, AppState>,
    equivalency_id: String,
    vault_document_id: Option<String>,
) -> CmdResult<()> {
    state.db.with_conn(|conn| {
        conn.execute(
            "UPDATE transfer_equivalency SET proof_document_id = ?1 WHERE id = ?2",
            rusqlite::params![vault_document_id, equivalency_id],
        )?;
        Ok(())
    })?;
    bump_transfer(&app, &state)?;
    Ok(())
}

#[derive(Debug, Deserialize)]
struct CommunityPayload {
    equivalencies: Option<Vec<ImportTransferRow>>,
}

#[derive(Debug, Deserialize)]
struct CommunityRowAlt {
    #[serde(rename = "sourceSchool")]
    source_school: Option<String>,
    #[serde(rename = "sourceSchoolID")]
    source_school_id: Option<String>,
    #[serde(rename = "sourceCode")]
    source_code: Option<String>,
    #[serde(rename = "sourceCourseCode")]
    source_course_code: Option<String>,
    #[serde(rename = "targetCode")]
    target_code: Option<String>,
    #[serde(rename = "targetCourseCode")]
    target_course_code: Option<String>,
    credits: Option<f64>,
    notes: Option<String>,
}

fn community_row_to_import(row: CommunityRowAlt) -> Option<ImportTransferRow> {
    let source_school = row
        .source_school
        .or(row.source_school_id)?
        .trim()
        .to_string();
    let source_code = row
        .source_code
        .or(row.source_course_code)?
        .trim()
        .to_string();
    let target_code = row
        .target_code
        .or(row.target_course_code)?
        .trim()
        .to_string();
    if source_school.is_empty() || source_code.is_empty() || target_code.is_empty() {
        return None;
    }
    Some(ImportTransferRow {
        source_school,
        source_code,
        target_code,
        credits: row.credits,
        notes: row.notes,
    })
}

#[tauri::command]
pub fn transfer_import_community_json(
    app: AppHandle,
    state: State<'_, AppState>,
    json_text: String,
) -> CmdResult<ImportTransferResult> {
    let trimmed = json_text.trim();
    if trimmed.is_empty() {
        return Err(crate::commands::CommandError {
            message: "Empty community JSON".into(),
        });
    }
    let rows: Vec<ImportTransferRow> = if let Ok(payload) = serde_json::from_str::<CommunityPayload>(trimmed) {
        payload.equivalencies.unwrap_or_default()
    } else if let Ok(list) = serde_json::from_str::<Vec<ImportTransferRow>>(trimmed) {
        list
    } else if let Ok(alt) = serde_json::from_str::<Vec<CommunityRowAlt>>(trimmed) {
        alt.into_iter().filter_map(community_row_to_import).collect()
    } else {
        return Err(crate::commands::CommandError {
            message: "Could not parse community JSON (expected array or {equivalencies:[]})".into(),
        });
    };
    let result = state
        .db
        .with_conn(|conn| Ok(import_equivalency_rows(conn, &rows)?))?;
    bump_transfer(&app, &state)?;
    Ok(result)
}

const ASSIST_SAMPLE_JSON: &str =
    include_str!("../../fixtures/assist_sample.json");

#[derive(Debug, Deserialize)]
struct AssistPayload {
    equivalencies: Option<Vec<AssistEquivalencyRow>>,
}

#[derive(Debug, Deserialize)]
struct AssistEquivalencyRow {
    #[serde(rename = "sourceSchoolName")]
    source_school_name: Option<String>,
    #[serde(rename = "source_school_name")]
    source_school_name_snake: Option<String>,
    #[serde(rename = "sourceCourseCode")]
    source_course_code: Option<String>,
    #[serde(rename = "source_course_code")]
    source_course_code_snake: Option<String>,
    #[serde(rename = "targetCourseCode")]
    target_course_code: Option<String>,
    #[serde(rename = "target_course_code")]
    target_course_code_snake: Option<String>,
    #[serde(rename = "sourceCredits")]
    source_credits: Option<f64>,
    #[serde(rename = "source_credits")]
    source_credits_snake: Option<f64>,
    #[serde(rename = "sourceCourseTitle")]
    source_course_title: Option<String>,
    #[serde(rename = "source_course_title")]
    source_course_title_snake: Option<String>,
}

fn assist_row_to_import(row: AssistEquivalencyRow) -> Option<ImportTransferRow> {
    let source_school = row
        .source_school_name
        .or(row.source_school_name_snake)?
        .trim()
        .to_string();
    let source_code = row
        .source_course_code
        .or(row.source_course_code_snake)?
        .trim()
        .to_string();
    let target_code = row
        .target_course_code
        .or(row.target_course_code_snake)?
        .trim()
        .to_string();
    if source_school.is_empty() || source_code.is_empty() || target_code.is_empty() {
        return None;
    }
    let title = row
        .source_course_title
        .or(row.source_course_title_snake)
        .unwrap_or_default();
    Some(ImportTransferRow {
        source_school,
        source_code,
        target_code,
        credits: row.source_credits.or(row.source_credits_snake),
        notes: if title.trim().is_empty() {
            Some("ASSIST import".into())
        } else {
            Some(format!("ASSIST: {title}"))
        },
    })
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TransferImportAssistInput {
    pub source_school_id: String,
    pub target_school_id: String,
    pub mode: Option<String>,
}

const ASSIST_ACADEMIC_YEAR_ID: i64 = 75;

#[derive(Debug, Deserialize)]
struct AssistInstitutionNode {
    #[serde(rename = "institutionId")]
    institution_id: Option<i64>,
    id: Option<i64>,
    #[serde(rename = "code")]
    institution_code: Option<String>,
    name: Option<String>,
    #[serde(default)]
    children: Vec<AssistInstitutionNode>,
}

async fn fetch_assist_institution_hierarchy(
    client: &reqwest::Client,
) -> Result<Vec<AssistInstitutionNode>, String> {
    let response = client
        .get("https://assist.org/api/institutions/hierarchy")
        .header(reqwest::header::ACCEPT, "application/json")
        .send()
        .await
        .map_err(|e| format!("ASSIST hierarchy fetch failed: {e}"))?;
    if !response.status().is_success() {
        return Err(format!("ASSIST hierarchy HTTP {}", response.status()));
    }
    response
        .json::<Vec<AssistInstitutionNode>>()
        .await
        .map_err(|e| format!("ASSIST hierarchy parse failed: {e}"))
}

fn find_institution_in_tree(nodes: &[AssistInstitutionNode], needle: &str) -> Option<i64> {
    let needle = needle.trim().to_lowercase().replace('_', " ");
    if needle.is_empty() {
        return None;
    }
    for node in nodes {
        let id = node.institution_id.or(node.id);
        let code = node
            .institution_code
            .as_deref()
            .unwrap_or("")
            .to_lowercase()
            .replace('_', " ");
        let name = node.name.as_deref().unwrap_or("").to_lowercase();
        if let Some(id) = id {
            if code == needle
                || name == needle
                || name.contains(&needle)
                || needle.contains(&code)
                || code.contains(&needle)
            {
                return Some(id);
            }
        }
        if let Some(found) = find_institution_in_tree(&node.children, &needle) {
            return Some(found);
        }
    }
    None
}

async fn resolve_assist_institution_id(client: &reqwest::Client, input: &str) -> Option<i64> {
    if let Ok(id) = input.parse::<i64>() {
        return Some(id);
    }
    let hierarchy = fetch_assist_institution_hierarchy(client).await.ok()?;
    find_institution_in_tree(&hierarchy, input)
}

async fn fetch_assist_mirror_json(source: &str, target: &str) -> Result<String, String> {
    let url = format!(
        "https://raw.githubusercontent.com/TL0225/college-planner-data/main/transfer/assist/{source}__{target}.json"
    );
    let response = reqwest::get(&url)
        .await
        .map_err(|e| format!("ASSIST mirror fetch failed: {e}"))?;
    if !response.status().is_success() {
        return Err(format!("ASSIST mirror HTTP {}", response.status()));
    }
    response
        .text()
        .await
        .map_err(|e| format!("ASSIST mirror read failed: {e}"))
}

fn parse_assist_json_rows(json_text: &str) -> Result<Vec<ImportTransferRow>, String> {
    let payload: AssistPayload = serde_json::from_str(json_text)
        .map_err(|e| format!("ASSIST JSON parse failed: {e}"))?;
    let rows: Vec<ImportTransferRow> = payload
        .equivalencies
        .unwrap_or_default()
        .into_iter()
        .filter_map(assist_row_to_import)
        .collect();
    if rows.is_empty() {
        return Err("No ASSIST equivalencies found in payload".into());
    }
    Ok(rows)
}

fn course_code_re() -> Regex {
    Regex::new(r"\b([A-Z]{2,5}\s*\d{1,3}[A-Z]{0,3})\b").expect("course code regex")
}

fn parse_assist_html_rows(html: &str, source_label: &str, _target_label: &str) -> Vec<ImportTransferRow> {
    let document = Html::parse_document(html);
    let code_re = course_code_re();
    let mut rows = Vec::new();
    let mut seen = std::collections::HashSet::new();

    if let Ok(row_sel) = Selector::parse("tr") {
        for tr in document.select(&row_sel) {
            let cells: Vec<String> = tr
                .select(&Selector::parse("td, th").unwrap())
                .map(|c| c.text().collect::<String>().trim().to_string())
                .filter(|c| !c.is_empty())
                .collect();
            if cells.len() < 2 {
                continue;
            }
            let source_code = cells[0].to_ascii_uppercase();
            let target_code = cells[1].to_ascii_uppercase();
            if !code_re.is_match(&source_code) || !code_re.is_match(&target_code) {
                continue;
            }
            let key = format!("{source_code}|{target_code}");
            if seen.insert(key) {
                rows.push(ImportTransferRow {
                    source_school: source_label.to_string(),
                    source_code,
                    target_code,
                    credits: cells.get(2).and_then(|c| c.parse().ok()),
                    notes: Some("ASSIST scrape".into()),
                });
            }
        }
    }

    if rows.is_empty() {
        let text: String = document.root_element().text().collect();
        let codes: Vec<String> = code_re
            .find_iter(&text.to_ascii_uppercase())
            .map(|m| m.as_str().to_string())
            .collect();
        for pair in codes.windows(2) {
            let key = format!("{}|{}", pair[0], pair[1]);
            if seen.insert(key) {
                rows.push(ImportTransferRow {
                    source_school: source_label.to_string(),
                    source_code: pair[0].clone(),
                    target_code: pair[1].clone(),
                    credits: None,
                    notes: Some("ASSIST scrape (heuristic)".into()),
                });
            }
        }
    }

    rows
}

#[derive(Debug, Deserialize)]
struct AssistAgreementList {
    reports: Option<Vec<AssistAgreementReport>>,
}

#[derive(Debug, Deserialize)]
struct AssistAgreementReport {
    key: Option<String>,
    label: Option<String>,
}

#[derive(Debug, Deserialize)]
struct AssistAgreementDetail {
    result: Option<AssistAgreementResult>,
}

#[derive(Debug, Deserialize)]
struct AssistAgreementResult {
    name: Option<String>,
    articulations: Option<Vec<AssistArticulation>>,
}

#[derive(Debug, Deserialize)]
struct AssistArticulation {
    #[serde(rename = "sendingArticulation")]
    sending_articulation: Option<AssistSendingArticulation>,
    #[serde(rename = "receivingArticulation")]
    receiving_articulation: Option<AssistReceivingArticulation>,
}

#[derive(Debug, Deserialize)]
struct AssistSendingArticulation {
    items: Option<Vec<AssistArticulationItem>>,
}

#[derive(Debug, Deserialize)]
struct AssistReceivingArticulation {
    items: Option<Vec<AssistArticulationItem>>,
}

#[derive(Debug, Deserialize)]
struct AssistArticulationItem {
    #[serde(rename = "course")]
    course: Option<AssistCourse>,
    items: Option<Vec<AssistArticulationItem>>,
}

#[derive(Debug, Deserialize)]
struct AssistCourse {
    #[serde(rename = "courseCode")]
    course_code: Option<String>,
    #[serde(rename = "courseTitle")]
    course_title: Option<String>,
    units: Option<f64>,
}

fn collect_assist_courses(item: &AssistArticulationItem, out: &mut Vec<(String, Option<f64>, Option<String>)>) {
    if let Some(course) = &item.course {
        if let Some(code) = course.course_code.as_ref().filter(|c| !c.trim().is_empty()) {
            out.push((
                code.trim().to_ascii_uppercase(),
                course.units,
                course.course_title.clone(),
            ));
        }
    }
    if let Some(children) = &item.items {
        for child in children {
            collect_assist_courses(child, out);
        }
    }
}

fn parse_assist_api_agreement(
    detail: &AssistAgreementResult,
    source_label: &str,
    target_label: &str,
) -> Vec<ImportTransferRow> {
    let mut rows = Vec::new();
    let articulations = detail.articulations.as_deref().unwrap_or_default();
    for articulation in articulations {
        let mut sending = Vec::new();
        let mut receiving = Vec::new();
        if let Some(sa) = &articulation.sending_articulation {
            for item in sa.items.as_deref().unwrap_or_default() {
                collect_assist_courses(item, &mut sending);
            }
        }
        if let Some(ra) = &articulation.receiving_articulation {
            for item in ra.items.as_deref().unwrap_or_default() {
                collect_assist_courses(item, &mut receiving);
            }
        }
        if sending.is_empty() || receiving.is_empty() {
            continue;
        }
        for (source_code, credits, title) in &sending {
            for (target_code, _, _) in &receiving {
                rows.push(ImportTransferRow {
                    source_school: source_label.to_string(),
                    source_code: source_code.clone(),
                    target_code: target_code.clone(),
                    credits: *credits,
                    notes: title
                        .as_ref()
                        .filter(|t| !t.trim().is_empty())
                        .map(|t| format!("ASSIST API: {t}")),
                });
            }
        }
    }
    if rows.is_empty() {
        if let Some(name) = detail.name.as_deref().filter(|n| !n.is_empty()) {
            rows.push(ImportTransferRow {
                source_school: source_label.to_string(),
                source_code: name.to_string(),
                target_code: target_label.to_string(),
                credits: None,
                notes: Some("ASSIST API agreement".into()),
            });
        }
    }
    rows
}

async fn fetch_assist_api_rows(
    source_id: i64,
    target_id: i64,
    source_label: &str,
    target_label: &str,
) -> Result<Vec<ImportTransferRow>, String> {
    let client = reqwest::Client::builder()
        .user_agent("CollegeDesktop/0.1 (+https://college.app)")
        .timeout(std::time::Duration::from_secs(25))
        .build()
        .map_err(|e| format!("HTTP client: {e}"))?;

    let list_url = format!(
        "https://assist.org/api/agreements?receivingInstitutionId={target_id}&sendingInstitutionId={source_id}&academicYearId={ASSIST_ACADEMIC_YEAR_ID}"
    );
    let list_resp = client
        .get(&list_url)
        .header(reqwest::header::ACCEPT, "application/json")
        .send()
        .await
        .map_err(|e| format!("ASSIST API list failed: {e}"))?;
    if !list_resp.status().is_success() {
        return Err(format!("ASSIST API list HTTP {}", list_resp.status()));
    }
    let list: AssistAgreementList = list_resp
        .json()
        .await
        .map_err(|e| format!("ASSIST API list parse failed: {e}"))?;

    let mut rows = Vec::new();
    for report in list.reports.unwrap_or_default() {
        let Some(key) = report.key.filter(|k| !k.is_empty()) else {
            continue;
        };
        let detail_url = format!(
            "https://assist.org/api/articulation/Agreements?Key={}",
            urlencoding::encode(&key)
        );
        let detail_resp = client
            .get(&detail_url)
            .header(reqwest::header::ACCEPT, "application/json")
            .send()
            .await
            .map_err(|e| format!("ASSIST API detail failed: {e}"))?;
        if !detail_resp.status().is_success() {
            continue;
        }
        let detail: AssistAgreementDetail = detail_resp
            .json()
            .await
            .map_err(|e| format!("ASSIST API detail parse failed: {e}"))?;
        if let Some(result) = detail.result {
            rows.extend(parse_assist_api_agreement(&result, source_label, target_label));
        }
    }
    if rows.is_empty() {
        return Err("ASSIST API returned no articulation rows".into());
    }
    Ok(rows)
}

async fn scrape_assist_rows(source: &str, target: &str) -> Result<Vec<ImportTransferRow>, String> {
    let source_label = source.to_string();
    let target_label = target.to_string();

    let client = reqwest::Client::builder()
        .user_agent("CollegeDesktop/0.1 (+https://college.app)")
        .timeout(std::time::Duration::from_secs(25))
        .build()
        .map_err(|e| format!("HTTP client: {e}"))?;

    let source_id = resolve_assist_institution_id(&client, source).await;
    let target_id = resolve_assist_institution_id(&client, target).await;
    if let (Some(source_id), Some(target_id)) = (source_id, target_id) {
        if let Ok(rows) =
            fetch_assist_api_rows(source_id, target_id, &source_label, &target_label).await
        {
            if !rows.is_empty() {
                return Ok(rows);
            }
        }
    }

    if let (Ok(source_id), Ok(target_id)) = (source.parse::<i64>(), target.parse::<i64>()) {
        if let Ok(rows) =
            fetch_assist_api_rows(source_id, target_id, &source_label, &target_label).await
        {
            if !rows.is_empty() {
                return Ok(rows);
            }
        }
    }

    let page_url = format!(
        "https://assist.org/transfer/results?year={ASSIST_ACADEMIC_YEAR_ID}&institution={}&agreement={}",
        urlencoding::encode(target),
        urlencoding::encode(source)
    );
    let response = client
        .get(&page_url)
        .send()
        .await
        .map_err(|e| format!("ASSIST page fetch failed: {e}"))?;
    if !response.status().is_success() {
        return Err(format!("ASSIST page HTTP {}", response.status()));
    }
    let html = response
        .text()
        .await
        .map_err(|e| format!("ASSIST page read failed: {e}"))?;
    let rows = parse_assist_html_rows(&html, &source_label, &target_label);
    if rows.is_empty() {
        return Err("ASSIST HTML scrape found no course rows".into());
    }
    Ok(rows)
}

async fn resolve_assist_rows(
    source: &str,
    target: &str,
    mode: Option<&str>,
) -> Result<Vec<ImportTransferRow>, String> {
    match mode {
        Some("scrape") => match scrape_assist_rows(source, target).await {
            Ok(rows) if !rows.is_empty() => Ok(rows),
            _ => match fetch_assist_mirror_json(source, target).await {
                Ok(json) => parse_assist_json_rows(&json),
                Err(_) => parse_assist_json_rows(ASSIST_SAMPLE_JSON),
            },
        },
        Some("live") => {
            let json = fetch_assist_mirror_json(source, target).await?;
            parse_assist_json_rows(&json)
        }
        _ => parse_assist_json_rows(ASSIST_SAMPLE_JSON),
    }
}

#[tauri::command]
pub async fn transfer_import_assist(
    app: AppHandle,
    state: State<'_, AppState>,
    input: TransferImportAssistInput,
) -> CmdResult<ImportTransferResult> {
    let source = input.source_school_id.trim().to_lowercase();
    let target = input.target_school_id.trim().to_lowercase();
    if source.is_empty() || target.is_empty() {
        return Err(crate::commands::CommandError {
            message: "Source and target school IDs required".into(),
        });
    }

    let rows = resolve_assist_rows(&source, &target, input.mode.as_deref())
        .await
        .map_err(|e| crate::commands::CommandError { message: e })?;

    let result = state
        .db
        .with_conn(|conn| Ok(import_equivalency_rows(conn, &rows)?))?;
    bump_transfer(&app, &state)?;
    Ok(result)
}
