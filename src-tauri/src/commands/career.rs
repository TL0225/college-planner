use crate::commands::CmdResult;
use crate::db::DbChangeEvent;
use crate::scrapers::fetch_html;
use crate::scrapers::{
    all_sources, JobBoardSource, JobBoardSyncResult, ScrapedJobListing,
};
use crate::AppState;
use chrono::Utc;
use rusqlite::OptionalExtension;
use scraper::{Html, Selector};
use serde::{Deserialize, Serialize};
use tauri::{AppHandle, Emitter, State};
use uuid::Uuid;

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct JobApplicationDto {
    pub id: String,
    pub company: String,
    pub role_title: String,
    pub status: String,
    pub location: String,
    pub url: String,
    pub applied_at: Option<String>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PipelineMetrics {
    pub interested: i64,
    pub applied: i64,
    pub interviewing: i64,
    pub offer: i64,
    pub rejected: i64,
    pub accepted: i64,
    pub total: i64,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct JobPostingDto {
    pub id: String,
    pub company: String,
    pub title: String,
    pub location: String,
    pub url: String,
    pub posted_at: Option<String>,
    pub tracked_application_id: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UpsertJobPostingInput {
    pub company: String,
    pub title: String,
    pub location: Option<String>,
    pub url: Option<String>,
    pub posted_at: Option<String>,
}

fn bump_career(app: &AppHandle, state: &AppState) -> CmdResult<()> {
    let rev = state.db.bump_revision("career")?;
    let _ = app.emit(
        "db:change",
        DbChangeEvent {
            domain: "career".into(),
            revision: rev,
        },
    );
    Ok(())
}

#[tauri::command]
pub fn career_list_applications(state: State<'_, AppState>) -> CmdResult<Vec<JobApplicationDto>> {
    state
        .db
        .with_conn(|conn| {
            let mut stmt = conn.prepare(
                "SELECT id, company, role_title, status, location, url, applied_at
                 FROM job_application ORDER BY sort_order ASC, updated_at DESC LIMIT 300",
            )?;
            let rows = stmt
                .query_map([], |r| {
                    Ok(JobApplicationDto {
                        id: r.get(0)?,
                        company: r.get(1)?,
                        role_title: r.get(2)?,
                        status: r.get(3)?,
                        location: r.get(4)?,
                        url: r.get(5)?,
                        applied_at: r.get(6)?,
                    })
                })?
                .collect::<Result<Vec<_>, _>>()?;
            Ok(rows)
        })
        .map_err(Into::into)
}

#[tauri::command]
pub fn career_pipeline_metrics(state: State<'_, AppState>) -> CmdResult<PipelineMetrics> {
    state
        .db
        .with_conn(|conn| {
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
        })
        .map_err(Into::into)
}

#[tauri::command]
pub fn career_list_job_postings(state: State<'_, AppState>) -> CmdResult<Vec<JobPostingDto>> {
    state
        .db
        .with_conn(|conn| {
            let mut stmt = conn.prepare(
                "SELECT id, company, title, location, url, posted_at, tracked_application_id
                 FROM workday_job_posting
                 ORDER BY posted_at IS NULL, posted_at DESC, company ASC
                 LIMIT 300",
            )?;
            let rows = stmt
                .query_map([], |r| {
                    Ok(JobPostingDto {
                        id: r.get(0)?,
                        company: r.get(1)?,
                        title: r.get(2)?,
                        location: r.get(3)?,
                        url: r.get(4)?,
                        posted_at: r.get(5)?,
                        tracked_application_id: r.get(6)?,
                    })
                })?
                .collect::<Result<Vec<_>, _>>()?;
            Ok(rows)
        })
        .map_err(Into::into)
}

struct ParsedJobPage {
    role_title: String,
    company: String,
    description: String,
}

fn meta_tag_content(document: &Html, key: &str) -> Option<String> {
    let sel = Selector::parse(&format!("meta[{key}]")).ok()?;
    document
        .select(&sel)
        .next()
        .and_then(|node| node.value().attr("content"))
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
}

fn page_title(document: &Html) -> String {
    let sel = Selector::parse("title").unwrap();
    document
        .select(&sel)
        .next()
        .map(|n| n.text().collect::<String>())
        .unwrap_or_default()
        .trim()
        .to_string()
}

fn company_from_domain(url: &str) -> String {
    let without_scheme = url
        .strip_prefix("https://")
        .or_else(|| url.strip_prefix("http://"))
        .unwrap_or(url);
    let host = without_scheme.split('/').next().unwrap_or(without_scheme);
    let host = host
        .strip_prefix("www.")
        .or_else(|| host.strip_prefix("careers."))
        .unwrap_or(host);
    let label = host.split('.').next().unwrap_or(host);
    let mut chars = label.chars();
    match chars.next() {
        None => String::new(),
        Some(first) => first.to_uppercase().collect::<String>() + chars.as_str(),
    }
}

fn clean_role_title(raw: &str, company_hint: &str) -> String {
    let mut title = raw.trim().to_string();
    if title.is_empty() {
        return title;
    }
    for suffix in [
        " | LinkedIn",
        " - LinkedIn",
        " | Indeed.com",
        " - Indeed",
        " | Glassdoor",
    ] {
        if let Some(stripped) = title.strip_suffix(suffix) {
            title = stripped.trim().to_string();
        }
    }
    if let Some((role, _company)) = title.split_once(" at ") {
        return role.trim().to_string();
    }
    if !company_hint.is_empty() {
        if let Some(stripped) = title.strip_suffix(&format!(" - {company_hint}")) {
            return stripped.trim().to_string();
        }
        if let Some(stripped) = title.strip_suffix(&format!(" | {company_hint}")) {
            return stripped.trim().to_string();
        }
    }
    if let Some((role, _tail)) = title.split_once(" - ") {
        return role.trim().to_string();
    }
    if let Some((role, _tail)) = title.split_once(" | ") {
        return role.trim().to_string();
    }
    title
}

fn parse_job_page(html: &str, url: &str) -> ParsedJobPage {
    let document = Html::parse_document(html);
    let raw_title = page_title(&document);
    let og_site = meta_tag_content(&document, r#"property="og:site_name""#)
        .or_else(|| meta_tag_content(&document, r#"name="application-name""#));
    let description = meta_tag_content(&document, r#"name="description""#)
        .or_else(|| meta_tag_content(&document, r#"property="og:description""#))
        .unwrap_or_default();
    let company = og_site
        .clone()
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| company_from_domain(url));
    let role_title = clean_role_title(&raw_title, &company);
    ParsedJobPage {
        role_title: if role_title.is_empty() {
            raw_title
        } else {
            role_title
        },
        company,
        description,
    }
}

/// Fetch a job posting URL, heuristically extract fields, and upsert into openings.
#[tauri::command]
pub async fn career_import_job_from_url(
    app: AppHandle,
    state: State<'_, AppState>,
    url: String,
) -> CmdResult<String> {
    let url = url.trim().to_string();
    if url.is_empty() {
        return Err(anyhow::anyhow!("url is required").into());
    }
    if !url.starts_with("http://") && !url.starts_with("https://") {
        return Err(anyhow::anyhow!("url must start with http:// or https://").into());
    }

    let (_preview, html) = fetch_html(&url)
        .await
        .map_err(|e| anyhow::anyhow!("Failed to fetch job page: {e}"))?;
    let parsed = parse_job_page(&html, &url);
    if parsed.role_title.trim().is_empty() && parsed.company.trim().is_empty() {
        return Err(anyhow::anyhow!("Could not extract a job title or company from the page").into());
    }

    let now = Utc::now().to_rfc3339();
    let raw_json = serde_json::json!({
        "source": "url_import",
        "description": parsed.description,
        "importedAt": now,
    })
    .to_string();

    let posting_id = state.db.with_conn(|conn| {
        let existing: Option<String> = conn
            .query_row(
                "SELECT id FROM workday_job_posting WHERE url = ?1 LIMIT 1",
                rusqlite::params![url],
                |r| r.get(0),
            )
            .optional()?;
        if let Some(id) = existing {
            conn.execute(
                "UPDATE workday_job_posting
                 SET company = ?1, title = ?2, raw_json = ?3, posted_at = COALESCE(posted_at, ?4)
                 WHERE id = ?5",
                rusqlite::params![
                    parsed.company.trim(),
                    parsed.role_title.trim(),
                    raw_json,
                    now,
                    id
                ],
            )?;
            Ok(id)
        } else {
            let id = Uuid::new_v4().to_string();
            conn.execute(
                "INSERT INTO workday_job_posting
                 (id, company, title, location, url, posted_at, tracked_application_id, raw_json)
                 VALUES (?1, ?2, ?3, '', ?4, ?5, NULL, ?6)",
                rusqlite::params![
                    id,
                    parsed.company.trim(),
                    parsed.role_title.trim(),
                    url,
                    now,
                    raw_json
                ],
            )?;
            Ok(id)
        }
    })?;

    bump_career(&app, &state)?;
    Ok(posting_id)
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SyncJobBoardsInput {
    pub sources: Option<Vec<String>>,
}

fn upsert_scraped_listings(
    state: &AppState,
    source: JobBoardSource,
    listings: &[ScrapedJobListing],
) -> CmdResult<(i64, i64, i64)> {
    upsert_scraped_listings_for_company(state, source.company_name(), listings)
}

fn upsert_scraped_listings_for_company(
    state: &AppState,
    company: &str,
    listings: &[ScrapedJobListing],
) -> CmdResult<(i64, i64, i64)> {
    let now = Utc::now().to_rfc3339();
    let mut imported = 0i64;
    let mut updated = 0i64;
    let mut skipped = 0i64;

    state.db.with_conn(|conn| {
        for listing in listings {
            if listing.url.trim().is_empty() && listing.title.trim().is_empty() {
                skipped += 1;
                continue;
            }
            let raw_json = serde_json::json!({
                "source": listing.source,
                "externalId": listing.external_id,
                "externalPath": listing.external_path,
                "syncedAt": now,
            })
            .to_string();

            let existing: Option<String> = if !listing.url.is_empty() {
                conn.query_row(
                    "SELECT id FROM workday_job_posting WHERE url = ?1 LIMIT 1",
                    rusqlite::params![listing.url],
                    |r| r.get(0),
                )
                .optional()?
            } else {
                None
            };

            if let Some(id) = existing {
                conn.execute(
                    "UPDATE workday_job_posting
                     SET company = ?1, title = ?2, location = ?3, raw_json = ?4,
                         posted_at = COALESCE(?5, posted_at)
                     WHERE id = ?6",
                    rusqlite::params![
                        company,
                        listing.title.trim(),
                        listing.location.trim(),
                        raw_json,
                        listing.posted_at,
                        id
                    ],
                )?;
                updated += 1;
            } else {
                let id = Uuid::new_v4().to_string();
                conn.execute(
                    "INSERT INTO workday_job_posting
                     (id, company, title, location, url, posted_at, tracked_application_id, raw_json)
                     VALUES (?1, ?2, ?3, ?4, ?5, ?6, NULL, ?7)",
                    rusqlite::params![
                        id,
                        company,
                        listing.title.trim(),
                        listing.location.trim(),
                        listing.url.trim(),
                        listing.posted_at,
                        raw_json
                    ],
                )?;
                imported += 1;
            }
        }
        Ok(())
    })?;

    Ok((imported, updated, skipped))
}

/// Scrape public job-board hubs (RemoteOK, Jobicy, Y Combinator) into Openings.
#[tauri::command]
pub async fn career_sync_job_boards(
    app: AppHandle,
    state: State<'_, AppState>,
    input: Option<SyncJobBoardsInput>,
) -> CmdResult<JobBoardSyncResult> {
    let sources: Vec<JobBoardSource> = if let Some(ids) = input.and_then(|i| i.sources) {
        let mut parsed = Vec::new();
        for id in ids {
            parsed.push(id.parse()?);
        }
        if parsed.is_empty() {
            all_sources().to_vec()
        } else {
            parsed
        }
    } else {
        all_sources().to_vec()
    };

    let mut source_results = Vec::new();

    for source in sources {
        let sync_result = if source == JobBoardSource::UsaJobs {
            crate::scrapers::sync_usajobs_listings(&state).await
        } else {
            crate::scrapers::sync_source_listings(source, None).await
        };
        match sync_result {
            Ok((mut row, listings)) => {
                let (imported, updated, skipped) = upsert_scraped_listings(&state, source, &listings)?;
                row.imported = imported;
                row.updated = updated;
                row.skipped = skipped;
                row.fetched = listings.len() as i64;
                source_results.push(row);
            }
            Err(e) => {
                source_results.push(crate::scrapers::JobBoardSyncSourceResult {
                    source: source.id().to_string(),
                    label: source.label().to_string(),
                    imported: 0,
                    updated: 0,
                    skipped: 0,
                    fetched: 0,
                    error: Some(e.to_string()),
                });
            }
        }
    }

    let result = JobBoardSyncResult {
        imported: source_results.iter().map(|s| s.imported).sum(),
        updated: source_results.iter().map(|s| s.updated).sum(),
        skipped: source_results.iter().map(|s| s.skipped).sum(),
        fetched: source_results.iter().map(|s| s.fetched).sum(),
        sources: source_results,
    };

    bump_career(&app, &state)?;
    Ok(result)
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct JobBoardCompanyDto {
    pub id: String,
    pub display_name: String,
    pub careers_url: String,
    pub platform: String,
    pub enabled: bool,
    pub sort_order: i64,
    pub last_synced_at: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UpsertJobBoardCompanyInput {
    pub id: Option<String>,
    pub display_name: String,
    pub careers_url: String,
    pub enabled: Option<bool>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SyncJobBoardCompaniesInput {
    pub company_ids: Option<Vec<String>>,
}

#[tauri::command]
pub fn career_list_job_board_companies(
    state: State<'_, AppState>,
) -> CmdResult<Vec<JobBoardCompanyDto>> {
    state
        .db
        .with_conn(|conn| {
            let mut stmt = conn.prepare(
                "SELECT id, display_name, careers_url, platform, enabled, sort_order, last_synced_at
                 FROM job_board_company
                 ORDER BY sort_order ASC, display_name ASC LIMIT 200",
            )?;
            let rows = stmt
                .query_map([], |r| {
                    Ok(JobBoardCompanyDto {
                        id: r.get(0)?,
                        display_name: r.get(1)?,
                        careers_url: r.get(2)?,
                        platform: r.get(3)?,
                        enabled: r.get::<_, i64>(4)? != 0,
                        sort_order: r.get(5)?,
                        last_synced_at: r.get(6)?,
                    })
                })?
                .collect::<Result<Vec<_>, _>>()?;
            Ok(rows)
        })
        .map_err(Into::into)
}

#[tauri::command]
pub fn career_upsert_job_board_company(
    app: AppHandle,
    state: State<'_, AppState>,
    input: UpsertJobBoardCompanyInput,
) -> CmdResult<String> {
    let url = input.careers_url.trim().to_string();
    if url.is_empty() {
        return Err(anyhow::anyhow!("Careers URL is required").into());
    }
    let platform = crate::scrapers::detect_platform(&url)
        .ok_or_else(|| {
            anyhow::anyhow!("Unsupported URL — Greenhouse, Workday, Lever, Oracle, iCIMS, or Talemetry/Jobvite")
        })?
        .id()
        .to_string();
    let name = if input.display_name.trim().is_empty() {
        platform.clone()
    } else {
        input.display_name.trim().to_string()
    };
    let enabled = input.enabled.unwrap_or(true);
    let now = Utc::now().to_rfc3339();

    let id = if let Some(existing) = input.id.filter(|s| !s.is_empty()) {
        state.db.with_conn(|conn| {
            conn.execute(
                "UPDATE job_board_company
                 SET display_name = ?1, careers_url = ?2, platform = ?3, enabled = ?4, updated_at = ?5
                 WHERE id = ?6",
                rusqlite::params![name, url, platform, if enabled { 1 } else { 0 }, now, existing],
            )?;
            Ok(())
        })?;
        existing
    } else {
        let id = Uuid::new_v4().to_string();
        state.db.with_conn(|conn| {
            let sort: i64 = conn
                .query_row(
                    "SELECT COALESCE(MAX(sort_order), 0) + 1 FROM job_board_company",
                    [],
                    |r| r.get(0),
                )
                .unwrap_or(1);
            conn.execute(
                "INSERT INTO job_board_company
                 (id, display_name, careers_url, platform, enabled, sort_order, last_synced_at, created_at, updated_at)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, NULL, ?7, ?7)",
                rusqlite::params![id, name, url, platform, if enabled { 1 } else { 0 }, sort, now],
            )?;
            Ok(())
        })?;
        id
    };
    bump_career(&app, &state)?;
    Ok(id)
}

#[tauri::command]
pub fn career_delete_job_board_company(
    app: AppHandle,
    state: State<'_, AppState>,
    id: String,
) -> CmdResult<()> {
    state.db.with_conn(|conn| {
        conn.execute(
            "DELETE FROM job_board_company WHERE id = ?1",
            rusqlite::params![id],
        )?;
        Ok(())
    })?;
    bump_career(&app, &state)?;
    Ok(())
}

#[tauri::command]
pub async fn career_sync_job_board_companies(
    app: AppHandle,
    state: State<'_, AppState>,
    input: Option<SyncJobBoardCompaniesInput>,
) -> CmdResult<JobBoardSyncResult> {
    let filter_ids = input.and_then(|i| i.company_ids).unwrap_or_default();
    let companies: Vec<(String, String, String, bool)> = state.db.with_conn(|conn| {
        let mut stmt = conn.prepare(
            "SELECT id, display_name, careers_url, enabled FROM job_board_company
             ORDER BY sort_order ASC, display_name ASC",
        )?;
        let rows = stmt
            .query_map([], |r| {
                Ok((
                    r.get::<_, String>(0)?,
                    r.get::<_, String>(1)?,
                    r.get::<_, String>(2)?,
                    r.get::<_, i64>(3)? != 0,
                ))
            })?
            .collect::<Result<Vec<_>, _>>()?;
        Ok(rows)
    })?;

    let targets: Vec<_> = companies
        .into_iter()
        .filter(|(id, _, _, enabled)| {
            if !filter_ids.is_empty() {
                filter_ids.iter().any(|f| f == id)
            } else {
                *enabled
            }
        })
        .collect();

    if targets.is_empty() {
        return Err(anyhow::anyhow!(
            "No company boards to sync — add a careers URL (Greenhouse, Workday, Lever, Oracle, iCIMS, Talemetry)"
        )
        .into());
    }

    let mut source_results = Vec::new();
    for (id, name, url, _) in targets {
        let platform = crate::scrapers::detect_platform(&url)
            .map(|p| p.label().to_string())
            .unwrap_or_else(|| "Company".into());
        match crate::scrapers::scrape_company_board(&name, &url).await {
            Ok(listings) => {
                let (imported, updated, skipped) =
                    upsert_scraped_listings_for_company(state.inner(), &name, &listings)?;
                let now = Utc::now().to_rfc3339();
                let _ = state.db.with_conn(|conn| {
                    conn.execute(
                        "UPDATE job_board_company SET last_synced_at = ?1, updated_at = ?1 WHERE id = ?2",
                        rusqlite::params![now, id],
                    )?;
                    Ok(())
                });
                source_results.push(crate::scrapers::JobBoardSyncSourceResult {
                    source: id,
                    label: format!("{name} ({platform})"),
                    imported,
                    updated,
                    skipped,
                    fetched: listings.len() as i64,
                    error: None,
                });
            }
            Err(e) => {
                source_results.push(crate::scrapers::JobBoardSyncSourceResult {
                    source: id,
                    label: format!("{name} ({platform})"),
                    imported: 0,
                    updated: 0,
                    skipped: 0,
                    fetched: 0,
                    error: Some(e.to_string()),
                });
            }
        }
    }

    let result = JobBoardSyncResult {
        imported: source_results.iter().map(|s| s.imported).sum(),
        updated: source_results.iter().map(|s| s.updated).sum(),
        skipped: source_results.iter().map(|s| s.skipped).sum(),
        fetched: source_results.iter().map(|s| s.fetched).sum(),
        sources: source_results,
    };
    bump_career(&app, &state)?;
    Ok(result)
}

#[derive(Debug, Serialize, Deserialize, Clone, Default)]
#[serde(rename_all = "camelCase")]
pub struct JobBoardSmartFilterCriteria {
    #[serde(default)]
    pub smart_query: String,
    #[serde(default)]
    pub keywords: Vec<String>,
    #[serde(default)]
    pub required_skills: Vec<String>,
    #[serde(default)]
    pub job_type_keywords: Vec<String>,
    #[serde(default)]
    pub schedule_keywords: Vec<String>,
    #[serde(default)]
    pub location_keywords: Vec<String>,
    pub min_match_score: Option<i32>,
    #[serde(default = "default_days_posted_filter")]
    pub days_posted_filter: String,
    #[serde(default)]
    pub hide_on_board: bool,
    #[serde(default)]
    pub show_closed: bool,
    #[serde(default)]
    pub closing_soon_only: bool,
    #[serde(default)]
    pub remote_only: bool,
}

fn default_days_posted_filter() -> String {
    "all".into()
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct JobBoardSmartBoardDto {
    pub id: String,
    pub name: String,
    pub company_ids: Vec<String>,
    pub filter: JobBoardSmartFilterCriteria,
    pub sort_order: i64,
    pub created_at: String,
    pub updated_at: String,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UpsertJobBoardSmartBoardInput {
    pub id: Option<String>,
    pub name: String,
    pub company_ids: Vec<String>,
    #[serde(default)]
    pub filter: JobBoardSmartFilterCriteria,
    pub sort_order: Option<i64>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct QuerySmartBoardPostingsInput {
    pub smart_board_id: String,
}

struct PostingRow {
    id: String,
    company: String,
    title: String,
    location: String,
    url: String,
    posted_at: Option<String>,
    tracked_application_id: Option<String>,
    raw_json: String,
}

fn token_set(values: &[String]) -> Vec<String> {
    let mut tokens = Vec::new();
    for value in values {
        for part in value.to_lowercase().split(|c: char| !c.is_alphanumeric() && c != '-') {
            if part.len() > 2 {
                tokens.push(part.to_string());
            }
        }
    }
    tokens.sort();
    tokens.dedup();
    tokens
}

fn posting_haystack(posting: &PostingRow) -> String {
    let description = serde_json::from_str::<serde_json::Value>(&posting.raw_json)
        .ok()
        .and_then(|v| {
            v.get("description")
                .and_then(|d| d.as_str())
                .map(|s| s.to_string())
        })
        .unwrap_or_default();
    [
        posting.title.as_str(),
        posting.location.as_str(),
        description.as_str(),
    ]
    .join(" ")
}

fn looks_remote(posting: &PostingRow) -> bool {
    let hay = format!("{} {} {}", posting.location, posting.title, posting_haystack(posting))
        .to_lowercase();
    hay.contains("remote") && !hay.contains("no remote") && !hay.contains("not remote")
}

fn matches_keyword_tokens(tokens: &[String], posting: &PostingRow) -> bool {
    if tokens.is_empty() {
        return true;
    }
    let hay = posting_haystack(posting).to_lowercase();
    let matched = tokens.iter().filter(|t| hay.contains(t.as_str())).count();
    (matched as f64) / (tokens.len() as f64) >= 0.35
}

fn parse_posted_at(iso: &str) -> Option<chrono::DateTime<chrono::Utc>> {
    chrono::DateTime::parse_from_rfc3339(iso)
        .ok()
        .map(|d| d.with_timezone(&chrono::Utc))
        .or_else(|| {
            chrono::NaiveDateTime::parse_from_str(iso, "%Y-%m-%dT%H:%M:%S%.fZ")
                .ok()
                .map(|d| d.and_utc())
        })
}

fn matches_days_posted_filter(posted_at: Option<&str>, filter: &str) -> bool {
    match filter {
        "all" => true,
        "today" | "day1" => {
            let Some(posted) = posted_at.and_then(|s| parse_posted_at(s)) else {
                return false;
            };
            let cutoff = Utc::now() - chrono::Duration::days(1);
            posted >= cutoff
        }
        "thisWeek" | "days7" => {
            let Some(posted) = posted_at.and_then(|s| parse_posted_at(s)) else {
                return false;
            };
            let cutoff = Utc::now() - chrono::Duration::days(7);
            posted >= cutoff
        }
        "days30" => {
            let Some(posted) = posted_at.and_then(|s| parse_posted_at(s)) else {
                return false;
            };
            let cutoff = Utc::now() - chrono::Duration::days(30);
            posted >= cutoff
        }
        "thirtyPlusDays" => {
            let Some(posted) = posted_at.and_then(|s| parse_posted_at(s)) else {
                return false;
            };
            let cutoff = Utc::now() - chrono::Duration::days(30);
            posted < cutoff
        }
        _ => true,
    }
}

fn filter_smart_board_postings(
    postings: Vec<PostingRow>,
    filter: &JobBoardSmartFilterCriteria,
) -> Vec<JobPostingDto> {
    let mut keyword_sources = filter.keywords.clone();
    keyword_sources.extend(filter.required_skills.clone());
    if !filter.smart_query.trim().is_empty() {
        keyword_sources.push(filter.smart_query.clone());
    }
    let smart_tokens = token_set(&keyword_sources);

    let mut results: Vec<JobPostingDto> = postings
        .into_iter()
        .filter(|p| {
            if filter.remote_only && !looks_remote(p) {
                return false;
            }
            if !matches_keyword_tokens(&smart_tokens, p) {
                return false;
            }
            if !matches_days_posted_filter(p.posted_at.as_deref(), &filter.days_posted_filter) {
                return false;
            }
            true
        })
        .map(|p| JobPostingDto {
            id: p.id,
            company: p.company,
            title: p.title,
            location: p.location,
            url: p.url,
            posted_at: p.posted_at,
            tracked_application_id: p.tracked_application_id,
        })
        .collect();

    results.sort_by(|a, b| {
        let a_date = a.posted_at.as_deref().and_then(parse_posted_at);
        let b_date = b.posted_at.as_deref().and_then(parse_posted_at);
        match (b_date, a_date) {
            (Some(bd), Some(ad)) => bd.cmp(&ad),
            (Some(_), None) => std::cmp::Ordering::Less,
            (None, Some(_)) => std::cmp::Ordering::Greater,
            (None, None) => a.title.cmp(&b.title),
        }
    });
    results.truncate(500);
    results
}

#[tauri::command]
pub fn career_list_smart_boards(state: State<'_, AppState>) -> CmdResult<Vec<JobBoardSmartBoardDto>> {
    state
        .db
        .with_conn(|conn| {
            let mut stmt = conn.prepare(
                "SELECT id, name, company_ids_json, filter_json, sort_order, created_at, updated_at
                 FROM job_board_smart_board
                 ORDER BY sort_order ASC, name ASC LIMIT 200",
            )?;
            let rows = stmt
                .query_map([], |r| {
                    let company_ids_json: String = r.get(2)?;
                    let filter_json: String = r.get(3)?;
                    let company_ids: Vec<String> =
                        serde_json::from_str(&company_ids_json).unwrap_or_default();
                    let filter: JobBoardSmartFilterCriteria =
                        serde_json::from_str(&filter_json).unwrap_or_default();
                    Ok(JobBoardSmartBoardDto {
                        id: r.get(0)?,
                        name: r.get(1)?,
                        company_ids,
                        filter,
                        sort_order: r.get(4)?,
                        created_at: r.get(5)?,
                        updated_at: r.get(6)?,
                    })
                })?
                .collect::<Result<Vec<_>, _>>()?;
            Ok(rows)
        })
        .map_err(Into::into)
}

#[tauri::command]
pub fn career_upsert_smart_board(
    app: AppHandle,
    state: State<'_, AppState>,
    input: UpsertJobBoardSmartBoardInput,
) -> CmdResult<String> {
    let name = input.name.trim();
    if name.is_empty() {
        return Err(anyhow::anyhow!("Board name is required").into());
    }
    if input.company_ids.is_empty() {
        return Err(anyhow::anyhow!("Select at least one company").into());
    }
    let now = Utc::now().to_rfc3339();
    let company_ids_json = serde_json::to_string(&input.company_ids)
        .map_err(|e| anyhow::anyhow!("Failed to encode company ids: {e}"))?;
    let filter_json = serde_json::to_string(&input.filter)
        .map_err(|e| anyhow::anyhow!("Failed to encode filter: {e}"))?;

    let id = if let Some(existing) = input.id.filter(|s| !s.is_empty()) {
        state.db.with_conn(|conn| {
            conn.execute(
                "UPDATE job_board_smart_board
                 SET name = ?1, company_ids_json = ?2, filter_json = ?3,
                     sort_order = COALESCE(?4, sort_order), updated_at = ?5
                 WHERE id = ?6",
                rusqlite::params![
                    name,
                    company_ids_json,
                    filter_json,
                    input.sort_order,
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
            let sort: i64 = input.sort_order.unwrap_or_else(|| {
                conn.query_row(
                    "SELECT COALESCE(MAX(sort_order), 0) + 1 FROM job_board_smart_board",
                    [],
                    |r| r.get(0),
                )
                .unwrap_or(1)
            });
            conn.execute(
                "INSERT INTO job_board_smart_board
                 (id, name, company_ids_json, filter_json, sort_order, created_at, updated_at)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?6)",
                rusqlite::params![id, name, company_ids_json, filter_json, sort, now],
            )?;
            Ok(())
        })?;
        id
    };
    bump_career(&app, &state)?;
    Ok(id)
}

#[tauri::command]
pub fn career_delete_smart_board(
    app: AppHandle,
    state: State<'_, AppState>,
    id: String,
) -> CmdResult<()> {
    state.db.with_conn(|conn| {
        conn.execute(
            "DELETE FROM job_board_smart_board WHERE id = ?1",
            rusqlite::params![id],
        )?;
        Ok(())
    })?;
    bump_career(&app, &state)?;
    Ok(())
}

#[tauri::command]
pub fn career_query_smart_board_postings(
    state: State<'_, AppState>,
    input: QuerySmartBoardPostingsInput,
) -> CmdResult<Vec<JobPostingDto>> {
    let board = state
        .db
        .with_conn(|conn| {
            conn.query_row(
                "SELECT company_ids_json, filter_json FROM job_board_smart_board WHERE id = ?1",
                rusqlite::params![input.smart_board_id],
                |r| {
                    let company_ids_json: String = r.get(0)?;
                    let filter_json: String = r.get(1)?;
                    Ok((company_ids_json, filter_json))
                },
            )
            .map_err(Into::into)
        })
        .map_err(|_| anyhow::anyhow!("Smart board not found"))?;

    let company_ids: Vec<String> = serde_json::from_str(&board.0).unwrap_or_default();
    let filter: JobBoardSmartFilterCriteria =
        serde_json::from_str(&board.1).unwrap_or_default();

    if company_ids.is_empty() {
        return Ok(Vec::new());
    }

    let placeholders = company_ids
        .iter()
        .map(|_| "?")
        .collect::<Vec<_>>()
        .join(", ");
    let company_names: Vec<String> = state.db.with_conn(|conn| {
        let sql = format!(
            "SELECT display_name FROM job_board_company WHERE id IN ({placeholders}) AND enabled = 1"
        );
        let mut stmt = conn.prepare(&sql)?;
        let rows = stmt
            .query_map(rusqlite::params_from_iter(company_ids.iter()), |r| {
                r.get(0)
            })?
            .collect::<Result<Vec<String>, _>>()?;
        Ok(rows)
    })?;

    if company_names.is_empty() {
        return Ok(Vec::new());
    }

    let name_placeholders = company_names
        .iter()
        .map(|_| "?")
        .collect::<Vec<_>>()
        .join(", ");
    let postings: Vec<PostingRow> = state.db.with_conn(|conn| {
        let sql = format!(
            "SELECT id, company, title, location, url, posted_at, tracked_application_id, raw_json
             FROM workday_job_posting
             WHERE company IN ({name_placeholders})
             ORDER BY posted_at IS NULL, posted_at DESC, title ASC
             LIMIT 2000"
        );
        let mut stmt = conn.prepare(&sql)?;
        let rows = stmt
            .query_map(rusqlite::params_from_iter(company_names.iter()), |r| {
                Ok(PostingRow {
                    id: r.get(0)?,
                    company: r.get(1)?,
                    title: r.get(2)?,
                    location: r.get(3)?,
                    url: r.get(4)?,
                    posted_at: r.get(5)?,
                    tracked_application_id: r.get(6)?,
                    raw_json: r.get(7)?,
                })
            })?
            .collect::<Result<Vec<_>, _>>()?;
        Ok(rows)
    })?;

    Ok(filter_smart_board_postings(postings, &filter))
}

#[tauri::command]
pub fn career_upsert_job_posting(
    app: AppHandle,
    state: State<'_, AppState>,
    input: UpsertJobPostingInput,
) -> CmdResult<String> {
    let id = Uuid::new_v4().to_string();
    state.db.with_conn(|conn| {
        conn.execute(
            "INSERT INTO workday_job_posting
             (id, company, title, location, url, posted_at, tracked_application_id, raw_json)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, NULL, '{}')",
            rusqlite::params![
                id,
                input.company.trim(),
                input.title.trim(),
                input.location.unwrap_or_default(),
                input.url.unwrap_or_default(),
                input.posted_at
            ],
        )?;
        Ok(())
    })?;
    bump_career(&app, &state)?;
    Ok(id)
}

#[tauri::command]
pub fn career_delete_job_posting(
    app: AppHandle,
    state: State<'_, AppState>,
    id: String,
) -> CmdResult<()> {
    state.db.with_conn(|conn| {
        conn.execute(
            "DELETE FROM workday_job_posting WHERE id = ?1",
            rusqlite::params![id],
        )?;
        Ok(())
    })?;
    bump_career(&app, &state)?;
    Ok(())
}

/// Create an application from a posting and link them.
#[tauri::command]
pub fn career_track_job_posting(
    app: AppHandle,
    state: State<'_, AppState>,
    id: String,
) -> CmdResult<String> {
    let now = Utc::now().to_rfc3339();
    let app_id = state.db.with_conn(|conn| {
        let (company, title, location, url): (String, String, String, String) = conn.query_row(
            "SELECT company, title, location, url FROM workday_job_posting WHERE id = ?1",
            rusqlite::params![id],
            |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?)),
        )?;
        let app_id = Uuid::new_v4().to_string();
        conn.execute(
            "INSERT INTO job_application
             (id, company, role_title, status, location, url, applied_at, notes, salary_text,
              sort_order, created_at, updated_at)
             VALUES (?1, ?2, ?3, 'interested', ?4, ?5, NULL, '', '', 0, ?6, ?6)",
            rusqlite::params![app_id, company, title, location, url, now],
        )?;
        conn.execute(
            "UPDATE workday_job_posting SET tracked_application_id = ?1 WHERE id = ?2",
            rusqlite::params![app_id, id],
        )?;
        Ok(app_id)
    })?;
    bump_career(&app, &state)?;
    Ok(app_id)
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PathEntryDto {
    pub id: String,
    pub organization: String,
    pub role_title: String,
    pub start_date: Option<String>,
    pub end_date: Option<String>,
    pub summary: String,
    pub sort_order: i64,
    pub resume_document_id: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UpsertPathEntryInput {
    pub id: Option<String>,
    pub organization: String,
    pub role_title: String,
    pub start_date: Option<String>,
    pub end_date: Option<String>,
    pub summary: Option<String>,
}

#[tauri::command]
pub fn career_list_path_entries(state: State<'_, AppState>) -> CmdResult<Vec<PathEntryDto>> {
    state
        .db
        .with_conn(|conn| {
            let mut stmt = conn.prepare(
                "SELECT id, organization, role_title, start_date, end_date, summary, sort_order,
                        resume_document_id
                 FROM career_path_entry
                 ORDER BY COALESCE(start_date, ''), sort_order ASC, organization ASC
                 LIMIT 200",
            )?;
            let rows = stmt
                .query_map([], |r| {
                    Ok(PathEntryDto {
                        id: r.get(0)?,
                        organization: r.get(1)?,
                        role_title: r.get(2)?,
                        start_date: r.get(3)?,
                        end_date: r.get(4)?,
                        summary: r.get(5)?,
                        sort_order: r.get(6)?,
                        resume_document_id: r.get(7)?,
                    })
                })?
                .collect::<Result<Vec<_>, _>>()?;
            Ok(rows)
        })
        .map_err(Into::into)
}

#[tauri::command]
pub fn career_upsert_path_entry(
    app: AppHandle,
    state: State<'_, AppState>,
    input: UpsertPathEntryInput,
) -> CmdResult<String> {
    let summary = input.summary.unwrap_or_default();
    let id = if let Some(existing) = input.id.filter(|s| !s.is_empty()) {
        state.db.with_conn(|conn| {
            conn.execute(
                "UPDATE career_path_entry
                 SET organization = ?1, role_title = ?2, start_date = ?3, end_date = ?4, summary = ?5
                 WHERE id = ?6",
                rusqlite::params![
                    input.organization,
                    input.role_title,
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
            let sort: i64 = conn
                .query_row(
                    "SELECT COALESCE(MAX(sort_order), 0) + 1 FROM career_path_entry",
                    [],
                    |r| r.get(0),
                )
                .unwrap_or(1);
            conn.execute(
                "INSERT INTO career_path_entry
                 (id, profile_id, organization, role_title, start_date, end_date, summary, sort_order)
                 VALUES (?1, NULL, ?2, ?3, ?4, ?5, ?6, ?7)",
                rusqlite::params![
                    id,
                    input.organization,
                    input.role_title,
                    input.start_date,
                    input.end_date,
                    summary,
                    sort
                ],
            )?;
            Ok(())
        })?;
        id
    };
    bump_career(&app, &state)?;
    Ok(id)
}

#[tauri::command]
pub fn career_delete_path_entry(
    app: AppHandle,
    state: State<'_, AppState>,
    id: String,
) -> CmdResult<()> {
    state.db.with_conn(|conn| {
        conn.execute(
            "DELETE FROM career_path_entry WHERE id = ?1",
            rusqlite::params![id],
        )?;
        Ok(())
    })?;
    bump_career(&app, &state)?;
    Ok(())
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CareerEventDto {
    pub id: String,
    pub application_id: Option<String>,
    pub title: String,
    pub occurs_at: String,
    pub kind: String,
    pub notes: String,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UpsertCareerEventInput {
    pub id: Option<String>,
    pub application_id: String,
    pub title: String,
    pub occurs_at: String,
    pub kind: Option<String>,
    pub notes: Option<String>,
}

#[tauri::command]
pub fn career_list_events(
    state: State<'_, AppState>,
    application_id: Option<String>,
) -> CmdResult<Vec<CareerEventDto>> {
    state
        .db
        .with_conn(|conn| {
            let map_row = |r: &rusqlite::Row<'_>| {
                Ok(CareerEventDto {
                    id: r.get(0)?,
                    application_id: r.get(1)?,
                    title: r.get(2)?,
                    occurs_at: r.get(3)?,
                    kind: r.get(4)?,
                    notes: r.get(5)?,
                })
            };
            let mut rows = Vec::new();
            if let Some(app_id) = application_id.filter(|s| !s.is_empty()) {
                let mut stmt = conn.prepare(
                    "SELECT id, application_id, title, occurs_at, kind, notes
                     FROM career_event
                     WHERE application_id = ?1
                     ORDER BY occurs_at DESC
                     LIMIT 100",
                )?;
                let mapped = stmt.query_map(rusqlite::params![app_id], map_row)?;
                for row in mapped {
                    rows.push(row?);
                }
            } else {
                let mut stmt = conn.prepare(
                    "SELECT id, application_id, title, occurs_at, kind, notes
                     FROM career_event
                     ORDER BY occurs_at DESC
                     LIMIT 200",
                )?;
                let mapped = stmt.query_map([], map_row)?;
                for row in mapped {
                    rows.push(row?);
                }
            }
            Ok(rows)
        })
        .map_err(Into::into)
}

#[tauri::command]
pub fn career_upsert_event(
    app: AppHandle,
    state: State<'_, AppState>,
    input: UpsertCareerEventInput,
) -> CmdResult<String> {
    let kind = input
        .kind
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| "interview".into());
    let notes = input.notes.unwrap_or_default();
    let id = if let Some(existing) = input.id.filter(|s| !s.is_empty()) {
        state.db.with_conn(|conn| {
            conn.execute(
                "UPDATE career_event
                 SET application_id = ?1, title = ?2, occurs_at = ?3, kind = ?4, notes = ?5
                 WHERE id = ?6",
                rusqlite::params![
                    input.application_id,
                    input.title.trim(),
                    input.occurs_at,
                    kind,
                    notes,
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
                "INSERT INTO career_event
                 (id, application_id, title, occurs_at, kind, notes)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
                rusqlite::params![
                    id,
                    input.application_id,
                    input.title.trim(),
                    input.occurs_at,
                    kind,
                    notes
                ],
            )?;
            Ok(())
        })?;
        id
    };
    bump_career(&app, &state)?;
    Ok(id)
}

#[tauri::command]
pub fn career_delete_event(
    app: AppHandle,
    state: State<'_, AppState>,
    id: String,
) -> CmdResult<()> {
    state.db.with_conn(|conn| {
        conn.execute(
            "DELETE FROM career_event WHERE id = ?1",
            rusqlite::params![id],
        )?;
        Ok(())
    })?;
    bump_career(&app, &state)?;
    Ok(())
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ResumeProfileDto {
    pub id: String,
    pub vault_doc_id: String,
    pub target_role: String,
    pub target_company: String,
    pub notes: String,
    pub updated_at: String,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UpsertResumeProfileInput {
    pub vault_doc_id: String,
    pub target_role: Option<String>,
    pub target_company: Option<String>,
    pub notes: Option<String>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ResumeMetrics {
    pub vault_resume_count: i64,
    pub profiles_with_notes_count: i64,
    pub last_match_score: Option<f64>,
}

#[tauri::command]
pub fn career_list_resume_profiles(state: State<'_, AppState>) -> CmdResult<Vec<ResumeProfileDto>> {
    state
        .db
        .with_conn(|conn| {
            let mut stmt = conn.prepare(
                "SELECT id, vault_doc_id, target_role, target_company, notes, updated_at
                 FROM career_resume_profile
                 ORDER BY updated_at DESC
                 LIMIT 300",
            )?;
            let rows = stmt
                .query_map([], |r| {
                    Ok(ResumeProfileDto {
                        id: r.get(0)?,
                        vault_doc_id: r.get(1)?,
                        target_role: r.get(2)?,
                        target_company: r.get(3)?,
                        notes: r.get(4)?,
                        updated_at: r.get(5)?,
                    })
                })?
                .collect::<Result<Vec<_>, _>>()?;
            Ok(rows)
        })
        .map_err(Into::into)
}

#[tauri::command]
pub fn career_upsert_resume_profile(
    app: AppHandle,
    state: State<'_, AppState>,
    input: UpsertResumeProfileInput,
) -> CmdResult<String> {
    let now = Utc::now().to_rfc3339();
    let target_role = input.target_role.unwrap_or_default();
    let target_company = input.target_company.unwrap_or_default();
    let notes = input.notes.unwrap_or_default();
    let id = state.db.with_conn(|conn| {
        if let Ok(existing) = conn.query_row(
            "SELECT id FROM career_resume_profile WHERE vault_doc_id = ?1",
            rusqlite::params![input.vault_doc_id],
            |r| r.get::<_, String>(0),
        ) {
            conn.execute(
                "UPDATE career_resume_profile
                 SET target_role = ?1, target_company = ?2, notes = ?3, updated_at = ?4
                 WHERE vault_doc_id = ?5",
                rusqlite::params![
                    target_role,
                    target_company,
                    notes,
                    now,
                    input.vault_doc_id
                ],
            )?;
            return Ok(existing);
        }
        let id = Uuid::new_v4().to_string();
        conn.execute(
            "INSERT INTO career_resume_profile
             (id, vault_doc_id, target_role, target_company, notes, updated_at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
            rusqlite::params![
                id,
                input.vault_doc_id,
                target_role,
                target_company,
                notes,
                now
            ],
        )?;
        Ok(id)
    })?;
    bump_career(&app, &state)?;
    Ok(id)
}

#[tauri::command]
pub fn career_resume_metrics(state: State<'_, AppState>) -> CmdResult<ResumeMetrics> {
    state
        .db
        .with_conn(|conn| {
            let vault_resume_count: i64 = conn
                .query_row(
                    "SELECT COUNT(*) FROM vault_document
                     WHERE category IN ('resume', 'general')
                        OR lower(title) LIKE '%resume%'
                        OR lower(title) LIKE '%cv%'",
                    [],
                    |r| r.get(0),
                )
                .unwrap_or(0);
            let profiles_with_notes_count: i64 = conn
                .query_row(
                    "SELECT COUNT(*) FROM career_resume_profile
                     WHERE trim(target_role) != ''
                        OR trim(target_company) != ''
                        OR trim(notes) != ''",
                    [],
                    |r| r.get(0),
                )
                .unwrap_or(0);
            let last_match_score = conn
                .query_row(
                    "SELECT value FROM app_settings WHERE key = 'career.lastMatchScore'",
                    [],
                    |r| r.get::<_, String>(0),
                )
                .ok()
                .and_then(|raw| {
                    serde_json::from_str::<serde_json::Value>(&raw)
                        .ok()
                        .and_then(|v| v.get("score").and_then(|s| s.as_f64()))
                });
            Ok(ResumeMetrics {
                vault_resume_count,
                profiles_with_notes_count,
                last_match_score,
            })
        })
        .map_err(Into::into)
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct BragEntryDto {
    pub id: String,
    pub title: String,
    pub occurred_at: Option<String>,
    pub summary: String,
    pub evidence_note: String,
    pub sort_order: i64,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UpsertBragEntryInput {
    pub id: Option<String>,
    pub title: String,
    pub occurred_at: Option<String>,
    pub summary: Option<String>,
    pub evidence_note: Option<String>,
}

#[tauri::command]
pub fn career_list_brag_entries(state: State<'_, AppState>) -> CmdResult<Vec<BragEntryDto>> {
    state
        .db
        .with_conn(|conn| {
            let mut stmt = conn.prepare(
                "SELECT id, title, occurred_at, summary, evidence_note, sort_order
                 FROM career_brag_entry
                 ORDER BY occurred_at IS NULL, occurred_at DESC, sort_order ASC, title ASC
                 LIMIT 200",
            )?;
            let rows = stmt
                .query_map([], |r| {
                    Ok(BragEntryDto {
                        id: r.get(0)?,
                        title: r.get(1)?,
                        occurred_at: r.get(2)?,
                        summary: r.get(3)?,
                        evidence_note: r.get(4)?,
                        sort_order: r.get(5)?,
                    })
                })?
                .collect::<Result<Vec<_>, _>>()?;
            Ok(rows)
        })
        .map_err(Into::into)
}

#[tauri::command]
pub fn career_upsert_brag_entry(
    app: AppHandle,
    state: State<'_, AppState>,
    input: UpsertBragEntryInput,
) -> CmdResult<String> {
    let summary = input.summary.unwrap_or_default();
    let evidence_note = input.evidence_note.unwrap_or_default();
    let id = if let Some(existing) = input.id.filter(|s| !s.is_empty()) {
        state.db.with_conn(|conn| {
            conn.execute(
                "UPDATE career_brag_entry
                 SET title = ?1, occurred_at = ?2, summary = ?3, evidence_note = ?4
                 WHERE id = ?5",
                rusqlite::params![
                    input.title.trim(),
                    input.occurred_at,
                    summary,
                    evidence_note,
                    existing
                ],
            )?;
            Ok(())
        })?;
        existing
    } else {
        let id = Uuid::new_v4().to_string();
        state.db.with_conn(|conn| {
            let sort: i64 = conn
                .query_row(
                    "SELECT COALESCE(MAX(sort_order), 0) + 1 FROM career_brag_entry",
                    [],
                    |r| r.get(0),
                )
                .unwrap_or(1);
            conn.execute(
                "INSERT INTO career_brag_entry
                 (id, title, occurred_at, summary, evidence_note, sort_order)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
                rusqlite::params![
                    id,
                    input.title.trim(),
                    input.occurred_at,
                    summary,
                    evidence_note,
                    sort
                ],
            )?;
            Ok(())
        })?;
        id
    };
    bump_career(&app, &state)?;
    Ok(id)
}

#[tauri::command]
pub fn career_delete_brag_entry(
    app: AppHandle,
    state: State<'_, AppState>,
    id: String,
) -> CmdResult<()> {
    state.db.with_conn(|conn| {
        conn.execute(
            "DELETE FROM career_brag_entry WHERE id = ?1",
            rusqlite::params![id],
        )?;
        Ok(())
    })?;
    bump_career(&app, &state)?;
    Ok(())
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct NetworkContactDto {
    pub id: String,
    pub name: String,
    pub organization: String,
    pub role_title: String,
    pub email: String,
    pub last_contact_at: Option<String>,
    pub notes: String,
    pub sort_order: i64,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UpsertNetworkContactInput {
    pub id: Option<String>,
    pub name: String,
    pub organization: Option<String>,
    pub role_title: Option<String>,
    pub email: Option<String>,
    pub last_contact_at: Option<String>,
    pub notes: Option<String>,
}

#[tauri::command]
pub fn career_list_network_contacts(
    state: State<'_, AppState>,
) -> CmdResult<Vec<NetworkContactDto>> {
    state
        .db
        .with_conn(|conn| {
            let mut stmt = conn.prepare(
                "SELECT id, name, organization, role_title, email, last_contact_at, notes, sort_order
                 FROM career_network_contact
                 ORDER BY sort_order ASC, name ASC
                 LIMIT 300",
            )?;
            let rows = stmt
                .query_map([], |r| {
                    Ok(NetworkContactDto {
                        id: r.get(0)?,
                        name: r.get(1)?,
                        organization: r.get(2)?,
                        role_title: r.get(3)?,
                        email: r.get(4)?,
                        last_contact_at: r.get(5)?,
                        notes: r.get(6)?,
                        sort_order: r.get(7)?,
                    })
                })?
                .collect::<Result<Vec<_>, _>>()?;
            Ok(rows)
        })
        .map_err(Into::into)
}

#[tauri::command]
pub fn career_upsert_network_contact(
    app: AppHandle,
    state: State<'_, AppState>,
    input: UpsertNetworkContactInput,
) -> CmdResult<String> {
    let organization = input.organization.unwrap_or_default();
    let role_title = input.role_title.unwrap_or_default();
    let email = input.email.unwrap_or_default();
    let notes = input.notes.unwrap_or_default();
    let id = if let Some(existing) = input.id.filter(|s| !s.is_empty()) {
        state.db.with_conn(|conn| {
            conn.execute(
                "UPDATE career_network_contact
                 SET name = ?1, organization = ?2, role_title = ?3, email = ?4,
                     last_contact_at = ?5, notes = ?6
                 WHERE id = ?7",
                rusqlite::params![
                    input.name.trim(),
                    organization,
                    role_title,
                    email,
                    input.last_contact_at,
                    notes,
                    existing
                ],
            )?;
            Ok(())
        })?;
        existing
    } else {
        let id = Uuid::new_v4().to_string();
        state.db.with_conn(|conn| {
            let sort: i64 = conn
                .query_row(
                    "SELECT COALESCE(MAX(sort_order), 0) + 1 FROM career_network_contact",
                    [],
                    |r| r.get(0),
                )
                .unwrap_or(1);
            conn.execute(
                "INSERT INTO career_network_contact
                 (id, name, organization, role_title, email, last_contact_at, notes, sort_order)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)",
                rusqlite::params![
                    id,
                    input.name.trim(),
                    organization,
                    role_title,
                    email,
                    input.last_contact_at,
                    notes,
                    sort
                ],
            )?;
            Ok(())
        })?;
        id
    };
    bump_career(&app, &state)?;
    Ok(id)
}

#[tauri::command]
pub fn career_delete_network_contact(
    app: AppHandle,
    state: State<'_, AppState>,
    id: String,
) -> CmdResult<()> {
    state.db.with_conn(|conn| {
        conn.execute(
            "DELETE FROM career_network_contact WHERE id = ?1",
            rusqlite::params![id],
        )?;
        Ok(())
    })?;
    bump_career(&app, &state)?;
    Ok(())
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct InterviewPrepDto {
    pub id: String,
    pub application_id: Option<String>,
    pub company: String,
    pub role_title: String,
    pub scheduled_at: Option<String>,
    pub status: String,
    pub notes: String,
    pub questions: String,
    pub sort_order: i64,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UpsertInterviewPrepInput {
    pub id: Option<String>,
    pub application_id: Option<String>,
    pub company: String,
    pub role_title: String,
    pub scheduled_at: Option<String>,
    pub status: Option<String>,
    pub notes: Option<String>,
    pub questions: Option<String>,
}

fn normalize_interview_status(status: Option<String>) -> String {
    match status.as_deref() {
        Some("completed") => "completed".into(),
        Some("cancelled") => "cancelled".into(),
        _ => "upcoming".into(),
    }
}

#[tauri::command]
pub fn career_list_interview_prep(
    state: State<'_, AppState>,
) -> CmdResult<Vec<InterviewPrepDto>> {
    state
        .db
        .with_conn(|conn| {
            let mut stmt = conn.prepare(
                "SELECT id, application_id, company, role_title, scheduled_at, status, notes, questions, sort_order
                 FROM career_interview_prep
                 ORDER BY
                   CASE status WHEN 'upcoming' THEN 0 WHEN 'completed' THEN 1 ELSE 2 END,
                   scheduled_at IS NULL,
                   scheduled_at ASC,
                   sort_order ASC
                 LIMIT 200",
            )?;
            let rows = stmt
                .query_map([], |r| {
                    Ok(InterviewPrepDto {
                        id: r.get(0)?,
                        application_id: r.get(1)?,
                        company: r.get(2)?,
                        role_title: r.get(3)?,
                        scheduled_at: r.get(4)?,
                        status: r.get(5)?,
                        notes: r.get(6)?,
                        questions: r.get(7)?,
                        sort_order: r.get(8)?,
                    })
                })?
                .collect::<Result<Vec<_>, _>>()?;
            Ok(rows)
        })
        .map_err(Into::into)
}

#[tauri::command]
pub fn career_upsert_interview_prep(
    app: AppHandle,
    state: State<'_, AppState>,
    input: UpsertInterviewPrepInput,
) -> CmdResult<String> {
    let status = normalize_interview_status(input.status);
    let notes = input.notes.unwrap_or_default();
    let questions = input.questions.unwrap_or_default();
    let application_id = input
        .application_id
        .filter(|s| !s.is_empty());
    let id = if let Some(existing) = input.id.filter(|s| !s.is_empty()) {
        state.db.with_conn(|conn| {
            conn.execute(
                "UPDATE career_interview_prep
                 SET application_id = ?1, company = ?2, role_title = ?3, scheduled_at = ?4,
                     status = ?5, notes = ?6, questions = ?7
                 WHERE id = ?8",
                rusqlite::params![
                    application_id,
                    input.company.trim(),
                    input.role_title.trim(),
                    input.scheduled_at,
                    status,
                    notes,
                    questions,
                    existing
                ],
            )?;
            Ok(())
        })?;
        existing
    } else {
        let id = Uuid::new_v4().to_string();
        state.db.with_conn(|conn| {
            let sort: i64 = conn
                .query_row(
                    "SELECT COALESCE(MAX(sort_order), 0) + 1 FROM career_interview_prep",
                    [],
                    |r| r.get(0),
                )
                .unwrap_or(1);
            conn.execute(
                "INSERT INTO career_interview_prep
                 (id, application_id, company, role_title, scheduled_at, status, notes, questions, sort_order)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)",
                rusqlite::params![
                    id,
                    application_id,
                    input.company.trim(),
                    input.role_title.trim(),
                    input.scheduled_at,
                    status,
                    notes,
                    questions,
                    sort
                ],
            )?;
            Ok(())
        })?;
        id
    };
    bump_career(&app, &state)?;
    Ok(id)
}

#[tauri::command]
pub fn career_delete_interview_prep(
    app: AppHandle,
    state: State<'_, AppState>,
    id: String,
) -> CmdResult<()> {
    state.db.with_conn(|conn| {
        conn.execute(
            "DELETE FROM career_interview_prep WHERE id = ?1",
            rusqlite::params![id],
        )?;
        Ok(())
    })?;
    bump_career(&app, &state)?;
    Ok(())
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PathMilestoneDto {
    pub id: String,
    pub path_entry_id: String,
    pub title: String,
    pub status: String,
    pub due_at: Option<String>,
    pub notes: String,
    pub lane: String,
    pub sort_order: i64,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UpsertPathMilestoneInput {
    pub id: Option<String>,
    pub path_entry_id: String,
    pub title: String,
    pub status: Option<String>,
    pub due_at: Option<String>,
    pub notes: Option<String>,
    pub lane: Option<String>,
}

fn normalize_milestone_status(status: Option<String>) -> String {
    match status.as_deref() {
        Some("in_progress") => "in_progress".into(),
        Some("done") => "done".into(),
        _ => "planned".into(),
    }
}

fn normalize_milestone_lane(lane: Option<String>) -> String {
    match lane.as_deref().map(|s| s.trim().to_ascii_lowercase()).as_deref() {
        Some("learning") => "learning".into(),
        Some("impact") => "impact".into(),
        Some("promotion") => "promotion".into(),
        _ => "general".into(),
    }
}

#[tauri::command]
pub fn career_list_path_milestones(
    state: State<'_, AppState>,
    path_entry_id: String,
) -> CmdResult<Vec<PathMilestoneDto>> {
    state
        .db
        .with_conn(|conn| {
            let mut stmt = conn.prepare(
                "SELECT id, path_entry_id, title, status, due_at, notes,
                        COALESCE(lane, 'general'), sort_order
                 FROM career_path_milestone
                 WHERE path_entry_id = ?1
                 ORDER BY
                   CASE COALESCE(lane, 'general')
                     WHEN 'learning' THEN 0
                     WHEN 'impact' THEN 1
                     WHEN 'promotion' THEN 2
                     ELSE 3
                   END,
                   sort_order ASC, due_at IS NULL, due_at ASC, title ASC
                 LIMIT 200",
            )?;
            let rows = stmt
                .query_map(rusqlite::params![path_entry_id], |r| {
                    Ok(PathMilestoneDto {
                        id: r.get(0)?,
                        path_entry_id: r.get(1)?,
                        title: r.get(2)?,
                        status: r.get(3)?,
                        due_at: r.get(4)?,
                        notes: r.get(5)?,
                        lane: r.get(6)?,
                        sort_order: r.get(7)?,
                    })
                })?
                .collect::<Result<Vec<_>, _>>()?;
            Ok(rows)
        })
        .map_err(Into::into)
}

#[tauri::command]
pub fn career_upsert_path_milestone(
    app: AppHandle,
    state: State<'_, AppState>,
    input: UpsertPathMilestoneInput,
) -> CmdResult<String> {
    let status = normalize_milestone_status(input.status);
    let lane = normalize_milestone_lane(input.lane);
    let notes = input.notes.unwrap_or_default();
    let due_at = input.due_at.filter(|s| !s.is_empty());
    let id = if let Some(existing) = input.id.filter(|s| !s.is_empty()) {
        state.db.with_conn(|conn| {
            conn.execute(
                "UPDATE career_path_milestone
                 SET path_entry_id = ?1, title = ?2, status = ?3, due_at = ?4, notes = ?5, lane = ?6
                 WHERE id = ?7",
                rusqlite::params![
                    input.path_entry_id,
                    input.title.trim(),
                    status,
                    due_at,
                    notes,
                    lane,
                    existing
                ],
            )?;
            Ok(())
        })?;
        existing
    } else {
        let id = Uuid::new_v4().to_string();
        state.db.with_conn(|conn| {
            let sort: i64 = conn
                .query_row(
                    "SELECT COALESCE(MAX(sort_order), 0) + 1 FROM career_path_milestone
                     WHERE path_entry_id = ?1",
                    rusqlite::params![input.path_entry_id],
                    |r| r.get(0),
                )
                .unwrap_or(1);
            conn.execute(
                "INSERT INTO career_path_milestone
                 (id, path_entry_id, title, status, due_at, notes, lane, sort_order)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)",
                rusqlite::params![
                    id,
                    input.path_entry_id,
                    input.title.trim(),
                    status,
                    due_at,
                    notes,
                    lane,
                    sort
                ],
            )?;
            Ok(())
        })?;
        id
    };
    bump_career(&app, &state)?;
    Ok(id)
}

#[tauri::command]
pub fn career_delete_path_milestone(
    app: AppHandle,
    state: State<'_, AppState>,
    id: String,
) -> CmdResult<()> {
    state.db.with_conn(|conn| {
        conn.execute(
            "DELETE FROM career_path_milestone WHERE id = ?1",
            rusqlite::params![id],
        )?;
        Ok(())
    })?;
    bump_career(&app, &state)?;
    Ok(())
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PathJournalEntryDto {
    pub id: String,
    pub path_entry_id: String,
    pub occurred_at: String,
    pub title: String,
    pub body: String,
    pub mood: String,
    pub sort_order: i64,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UpsertPathJournalEntryInput {
    pub id: Option<String>,
    pub path_entry_id: String,
    pub occurred_at: String,
    pub title: Option<String>,
    pub body: Option<String>,
    pub mood: Option<String>,
}

fn normalize_journal_mood(mood: Option<String>) -> String {
    match mood.as_deref() {
        Some("great") => "great".into(),
        Some("ok") => "ok".into(),
        Some("hard") => "hard".into(),
        _ => String::new(),
    }
}

#[tauri::command]
pub fn career_list_path_journal_entries(
    state: State<'_, AppState>,
    path_entry_id: String,
) -> CmdResult<Vec<PathJournalEntryDto>> {
    state
        .db
        .with_conn(|conn| {
            let mut stmt = conn.prepare(
                "SELECT id, path_entry_id, occurred_at, title, body, mood, sort_order
                 FROM career_path_journal_entry
                 WHERE path_entry_id = ?1
                 ORDER BY occurred_at DESC, sort_order ASC, title ASC
                 LIMIT 200",
            )?;
            let rows = stmt
                .query_map(rusqlite::params![path_entry_id], |r| {
                    Ok(PathJournalEntryDto {
                        id: r.get(0)?,
                        path_entry_id: r.get(1)?,
                        occurred_at: r.get(2)?,
                        title: r.get(3)?,
                        body: r.get(4)?,
                        mood: r.get(5)?,
                        sort_order: r.get(6)?,
                    })
                })?
                .collect::<Result<Vec<_>, _>>()?;
            Ok(rows)
        })
        .map_err(Into::into)
}

#[tauri::command]
pub fn career_upsert_path_journal_entry(
    app: AppHandle,
    state: State<'_, AppState>,
    input: UpsertPathJournalEntryInput,
) -> CmdResult<String> {
    let title = input.title.unwrap_or_default();
    let body = input.body.unwrap_or_default();
    let mood = normalize_journal_mood(input.mood);
    let occurred_at = input.occurred_at.trim();
    if occurred_at.is_empty() {
        return Err(anyhow::anyhow!("occurred_at is required").into());
    }
    let id = if let Some(existing) = input.id.filter(|s| !s.is_empty()) {
        state.db.with_conn(|conn| {
            conn.execute(
                "UPDATE career_path_journal_entry
                 SET path_entry_id = ?1, occurred_at = ?2, title = ?3, body = ?4, mood = ?5
                 WHERE id = ?6",
                rusqlite::params![
                    input.path_entry_id,
                    occurred_at,
                    title.trim(),
                    body,
                    mood,
                    existing
                ],
            )?;
            Ok(())
        })?;
        existing
    } else {
        let id = Uuid::new_v4().to_string();
        state.db.with_conn(|conn| {
            let sort: i64 = conn
                .query_row(
                    "SELECT COALESCE(MAX(sort_order), 0) + 1 FROM career_path_journal_entry
                     WHERE path_entry_id = ?1",
                    rusqlite::params![input.path_entry_id],
                    |r| r.get(0),
                )
                .unwrap_or(1);
            conn.execute(
                "INSERT INTO career_path_journal_entry
                 (id, path_entry_id, occurred_at, title, body, mood, sort_order)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
                rusqlite::params![
                    id,
                    input.path_entry_id,
                    occurred_at,
                    title.trim(),
                    body,
                    mood,
                    sort
                ],
            )?;
            Ok(())
        })?;
        id
    };
    bump_career(&app, &state)?;
    Ok(id)
}

#[tauri::command]
pub fn career_delete_path_journal_entry(
    app: AppHandle,
    state: State<'_, AppState>,
    id: String,
) -> CmdResult<()> {
    state.db.with_conn(|conn| {
        conn.execute(
            "DELETE FROM career_path_journal_entry WHERE id = ?1",
            rusqlite::params![id],
        )?;
        Ok(())
    })?;
    bump_career(&app, &state)?;
    Ok(())
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PathDocumentDto {
    pub id: String,
    pub path_entry_id: String,
    pub vault_doc_id: String,
    pub note: String,
    pub title: String,
    pub category: String,
    pub has_file: bool,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LinkPathDocumentInput {
    pub path_entry_id: String,
    pub vault_doc_id: String,
    pub note: Option<String>,
}

#[tauri::command]
pub fn career_list_path_documents(
    state: State<'_, AppState>,
    path_entry_id: String,
) -> CmdResult<Vec<PathDocumentDto>> {
    state
        .db
        .with_conn(|conn| {
            let mut stmt = conn.prepare(
                "SELECT cpd.id, cpd.path_entry_id, cpd.vault_doc_id, cpd.note,
                        COALESCE(v.title, ''), COALESCE(v.category, 'general'),
                        CASE WHEN COALESCE(v.relative_path, '') != '' THEN 1 ELSE 0 END
                 FROM career_path_document cpd
                 LEFT JOIN vault_document v ON v.id = cpd.vault_doc_id
                 WHERE cpd.path_entry_id = ?1
                 ORDER BY v.title ASC, cpd.id ASC
                 LIMIT 200",
            )?;
            let rows = stmt
                .query_map(rusqlite::params![path_entry_id], |r| {
                    Ok(PathDocumentDto {
                        id: r.get(0)?,
                        path_entry_id: r.get(1)?,
                        vault_doc_id: r.get(2)?,
                        note: r.get(3)?,
                        title: r.get(4)?,
                        category: r.get(5)?,
                        has_file: r.get::<_, i64>(6)? != 0,
                    })
                })?
                .collect::<Result<Vec<_>, _>>()?;
            Ok(rows)
        })
        .map_err(Into::into)
}

#[tauri::command]
pub fn career_link_path_document(
    app: AppHandle,
    state: State<'_, AppState>,
    input: LinkPathDocumentInput,
) -> CmdResult<String> {
    let note = input.note.unwrap_or_default();
    let id = state.db.with_conn(|conn| {
        if let Ok(existing) = conn.query_row(
            "SELECT id FROM career_path_document
             WHERE path_entry_id = ?1 AND vault_doc_id = ?2",
            rusqlite::params![input.path_entry_id, input.vault_doc_id],
            |r| r.get::<_, String>(0),
        ) {
            conn.execute(
                "UPDATE career_path_document SET note = ?1 WHERE id = ?2",
                rusqlite::params![note, existing],
            )?;
            return Ok(existing);
        }
        let id = Uuid::new_v4().to_string();
        conn.execute(
            "INSERT INTO career_path_document (id, path_entry_id, vault_doc_id, note)
             VALUES (?1, ?2, ?3, ?4)",
            rusqlite::params![id, input.path_entry_id, input.vault_doc_id, note],
        )?;
        Ok(id)
    })?;
    bump_career(&app, &state)?;
    Ok(id)
}

#[tauri::command]
pub fn career_unlink_path_document(
    app: AppHandle,
    state: State<'_, AppState>,
    id: String,
) -> CmdResult<()> {
    state.db.with_conn(|conn| {
        conn.execute(
            "DELETE FROM career_path_document WHERE id = ?1",
            rusqlite::params![id],
        )?;
        Ok(())
    })?;
    bump_career(&app, &state)?;
    Ok(())
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PathPromotionDto {
    pub id: String,
    pub path_entry_id: String,
    pub title: String,
    pub effective_at: Option<String>,
    pub notes: String,
    pub sort_order: i64,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UpsertPathPromotionInput {
    pub id: Option<String>,
    pub path_entry_id: String,
    pub title: String,
    pub effective_at: Option<String>,
    pub notes: Option<String>,
}

#[tauri::command]
pub fn career_list_path_promotions(
    state: State<'_, AppState>,
    path_entry_id: String,
) -> CmdResult<Vec<PathPromotionDto>> {
    state
        .db
        .with_conn(|conn| {
            let mut stmt = conn.prepare(
                "SELECT id, path_entry_id, title, effective_at, notes, sort_order
                 FROM career_path_promotion
                 WHERE path_entry_id = ?1
                 ORDER BY effective_at DESC, sort_order ASC, title ASC
                 LIMIT 200",
            )?;
            let rows = stmt
                .query_map(rusqlite::params![path_entry_id], |r| {
                    Ok(PathPromotionDto {
                        id: r.get(0)?,
                        path_entry_id: r.get(1)?,
                        title: r.get(2)?,
                        effective_at: r.get(3)?,
                        notes: r.get(4)?,
                        sort_order: r.get(5)?,
                    })
                })?
                .collect::<Result<Vec<_>, _>>()?;
            Ok(rows)
        })
        .map_err(Into::into)
}

#[tauri::command]
pub fn career_upsert_path_promotion(
    app: AppHandle,
    state: State<'_, AppState>,
    input: UpsertPathPromotionInput,
) -> CmdResult<String> {
    let title = input.title.trim();
    if title.is_empty() {
        return Err(anyhow::anyhow!("title is required").into());
    }
    let notes = input.notes.unwrap_or_default();
    let effective_at = input
        .effective_at
        .filter(|s| !s.trim().is_empty())
        .map(|s| s.trim().to_string());
    let id = if let Some(existing) = input.id.filter(|s| !s.is_empty()) {
        state.db.with_conn(|conn| {
            conn.execute(
                "UPDATE career_path_promotion
                 SET path_entry_id = ?1, title = ?2, effective_at = ?3, notes = ?4
                 WHERE id = ?5",
                rusqlite::params![
                    input.path_entry_id,
                    title,
                    effective_at,
                    notes,
                    existing
                ],
            )?;
            Ok(())
        })?;
        existing
    } else {
        let id = Uuid::new_v4().to_string();
        state.db.with_conn(|conn| {
            let sort: i64 = conn
                .query_row(
                    "SELECT COALESCE(MAX(sort_order), 0) + 1 FROM career_path_promotion
                     WHERE path_entry_id = ?1",
                    rusqlite::params![input.path_entry_id],
                    |r| r.get(0),
                )
                .unwrap_or(1);
            conn.execute(
                "INSERT INTO career_path_promotion
                 (id, path_entry_id, title, effective_at, notes, sort_order)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
                rusqlite::params![id, input.path_entry_id, title, effective_at, notes, sort],
            )?;
            Ok(())
        })?;
        id
    };
    bump_career(&app, &state)?;
    Ok(id)
}

#[tauri::command]
pub fn career_delete_path_promotion(
    app: AppHandle,
    state: State<'_, AppState>,
    id: String,
) -> CmdResult<()> {
    state.db.with_conn(|conn| {
        conn.execute(
            "DELETE FROM career_path_promotion WHERE id = ?1",
            rusqlite::params![id],
        )?;
        Ok(())
    })?;
    bump_career(&app, &state)?;
    Ok(())
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PathPersonDto {
    pub id: String,
    pub path_entry_id: String,
    pub name: String,
    pub role_title: String,
    pub relationship: String,
    pub notes: String,
    pub sort_order: i64,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UpsertPathPersonInput {
    pub id: Option<String>,
    pub path_entry_id: String,
    pub name: String,
    pub role_title: Option<String>,
    pub relationship: Option<String>,
    pub notes: Option<String>,
}

#[tauri::command]
pub fn career_list_path_people(
    state: State<'_, AppState>,
    path_entry_id: String,
) -> CmdResult<Vec<PathPersonDto>> {
    state
        .db
        .with_conn(|conn| {
            let mut stmt = conn.prepare(
                "SELECT id, path_entry_id, name, role_title, relationship, notes, sort_order
                 FROM career_path_person
                 WHERE path_entry_id = ?1
                 ORDER BY sort_order ASC, name ASC
                 LIMIT 200",
            )?;
            let rows = stmt
                .query_map(rusqlite::params![path_entry_id], |r| {
                    Ok(PathPersonDto {
                        id: r.get(0)?,
                        path_entry_id: r.get(1)?,
                        name: r.get(2)?,
                        role_title: r.get(3)?,
                        relationship: r.get(4)?,
                        notes: r.get(5)?,
                        sort_order: r.get(6)?,
                    })
                })?
                .collect::<Result<Vec<_>, _>>()?;
            Ok(rows)
        })
        .map_err(Into::into)
}

#[tauri::command]
pub fn career_upsert_path_person(
    app: AppHandle,
    state: State<'_, AppState>,
    input: UpsertPathPersonInput,
) -> CmdResult<String> {
    let name = input.name.trim();
    if name.is_empty() {
        return Err(anyhow::anyhow!("name is required").into());
    }
    let role_title = input.role_title.unwrap_or_default();
    let relationship = input.relationship.unwrap_or_default();
    let notes = input.notes.unwrap_or_default();
    let id = if let Some(existing) = input.id.filter(|s| !s.is_empty()) {
        state.db.with_conn(|conn| {
            conn.execute(
                "UPDATE career_path_person
                 SET path_entry_id = ?1, name = ?2, role_title = ?3, relationship = ?4, notes = ?5
                 WHERE id = ?6",
                rusqlite::params![
                    input.path_entry_id,
                    name,
                    role_title.trim(),
                    relationship.trim(),
                    notes,
                    existing
                ],
            )?;
            Ok(())
        })?;
        existing
    } else {
        let id = Uuid::new_v4().to_string();
        state.db.with_conn(|conn| {
            let sort: i64 = conn
                .query_row(
                    "SELECT COALESCE(MAX(sort_order), 0) + 1 FROM career_path_person
                     WHERE path_entry_id = ?1",
                    rusqlite::params![input.path_entry_id],
                    |r| r.get(0),
                )
                .unwrap_or(1);
            conn.execute(
                "INSERT INTO career_path_person
                 (id, path_entry_id, name, role_title, relationship, notes, sort_order)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
                rusqlite::params![
                    id,
                    input.path_entry_id,
                    name,
                    role_title.trim(),
                    relationship.trim(),
                    notes,
                    sort
                ],
            )?;
            Ok(())
        })?;
        id
    };
    bump_career(&app, &state)?;
    Ok(id)
}

#[tauri::command]
pub fn career_delete_path_person(
    app: AppHandle,
    state: State<'_, AppState>,
    id: String,
) -> CmdResult<()> {
    state.db.with_conn(|conn| {
        conn.execute(
            "DELETE FROM career_path_person WHERE id = ?1",
            rusqlite::params![id],
        )?;
        Ok(())
    })?;
    bump_career(&app, &state)?;
    Ok(())
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PathDecisionJournalDto {
    pub path_entry_id: String,
    pub why_accepted: String,
    pub alternatives: String,
    pub expected_benefits: String,
    pub concerns: String,
    pub success_criteria: String,
    pub why_left: String,
    pub lessons: String,
    pub would_do_differently: String,
    pub updated_at: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UpsertPathDecisionJournalInput {
    pub path_entry_id: String,
    pub why_accepted: Option<String>,
    pub alternatives: Option<String>,
    pub expected_benefits: Option<String>,
    pub concerns: Option<String>,
    pub success_criteria: Option<String>,
    pub why_left: Option<String>,
    pub lessons: Option<String>,
    pub would_do_differently: Option<String>,
}

#[tauri::command]
pub fn career_get_path_decision_journal(
    state: State<'_, AppState>,
    path_entry_id: String,
) -> CmdResult<PathDecisionJournalDto> {
    state
        .db
        .with_conn(|conn| {
            let mut stmt = conn.prepare(
                "SELECT path_entry_id, why_accepted, alternatives, expected_benefits, concerns,
                        success_criteria, why_left, lessons, would_do_differently, updated_at
                 FROM career_path_decision_journal WHERE path_entry_id = ?1",
            )?;
            let row = stmt
                .query_row(rusqlite::params![path_entry_id], |r| {
                    Ok(PathDecisionJournalDto {
                        path_entry_id: r.get(0)?,
                        why_accepted: r.get(1)?,
                        alternatives: r.get(2)?,
                        expected_benefits: r.get(3)?,
                        concerns: r.get(4)?,
                        success_criteria: r.get(5)?,
                        why_left: r.get(6)?,
                        lessons: r.get(7)?,
                        would_do_differently: r.get(8)?,
                        updated_at: r.get(9)?,
                    })
                })
                .optional()?;
            Ok(row.unwrap_or(PathDecisionJournalDto {
                path_entry_id,
                why_accepted: String::new(),
                alternatives: String::new(),
                expected_benefits: String::new(),
                concerns: String::new(),
                success_criteria: String::new(),
                why_left: String::new(),
                lessons: String::new(),
                would_do_differently: String::new(),
                updated_at: None,
            }))
        })
        .map_err(Into::into)
}

#[tauri::command]
pub fn career_upsert_path_decision_journal(
    app: AppHandle,
    state: State<'_, AppState>,
    input: UpsertPathDecisionJournalInput,
) -> CmdResult<()> {
    let now = Utc::now().to_rfc3339();
    state.db.with_conn(|conn| {
        conn.execute(
            "INSERT INTO career_path_decision_journal
             (path_entry_id, why_accepted, alternatives, expected_benefits, concerns,
              success_criteria, why_left, lessons, would_do_differently, updated_at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10)
             ON CONFLICT(path_entry_id) DO UPDATE SET
               why_accepted = excluded.why_accepted,
               alternatives = excluded.alternatives,
               expected_benefits = excluded.expected_benefits,
               concerns = excluded.concerns,
               success_criteria = excluded.success_criteria,
               why_left = excluded.why_left,
               lessons = excluded.lessons,
               would_do_differently = excluded.would_do_differently,
               updated_at = excluded.updated_at",
            rusqlite::params![
                input.path_entry_id,
                input.why_accepted.unwrap_or_default(),
                input.alternatives.unwrap_or_default(),
                input.expected_benefits.unwrap_or_default(),
                input.concerns.unwrap_or_default(),
                input.success_criteria.unwrap_or_default(),
                input.why_left.unwrap_or_default(),
                input.lessons.unwrap_or_default(),
                input.would_do_differently.unwrap_or_default(),
                now
            ],
        )?;
        Ok(())
    })?;
    bump_career(&app, &state)?;
    Ok(())
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PathBenefitDto {
    pub id: String,
    pub path_entry_id: String,
    pub title: String,
    pub is_active: bool,
    pub notes: String,
    pub sort_order: i64,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UpsertPathBenefitInput {
    pub id: Option<String>,
    pub path_entry_id: String,
    pub title: String,
    pub is_active: Option<bool>,
    pub notes: Option<String>,
}

#[tauri::command]
pub fn career_list_path_benefits(
    state: State<'_, AppState>,
    path_entry_id: String,
) -> CmdResult<Vec<PathBenefitDto>> {
    state
        .db
        .with_conn(|conn| {
            let mut stmt = conn.prepare(
                "SELECT id, path_entry_id, title, is_active, notes, sort_order
                 FROM career_path_benefit
                 WHERE path_entry_id = ?1
                 ORDER BY sort_order ASC, title ASC
                 LIMIT 200",
            )?;
            let rows = stmt
                .query_map(rusqlite::params![path_entry_id], |r| {
                    Ok(PathBenefitDto {
                        id: r.get(0)?,
                        path_entry_id: r.get(1)?,
                        title: r.get(2)?,
                        is_active: r.get::<_, i64>(3)? != 0,
                        notes: r.get(4)?,
                        sort_order: r.get(5)?,
                    })
                })?
                .collect::<Result<Vec<_>, _>>()?;
            Ok(rows)
        })
        .map_err(Into::into)
}

#[tauri::command]
pub fn career_upsert_path_benefit(
    app: AppHandle,
    state: State<'_, AppState>,
    input: UpsertPathBenefitInput,
) -> CmdResult<String> {
    let title = input.title.trim();
    if title.is_empty() {
        return Err(anyhow::anyhow!("title is required").into());
    }
    let notes = input.notes.unwrap_or_default();
    let is_active = if input.is_active.unwrap_or(false) { 1 } else { 0 };
    let id = if let Some(existing) = input.id.filter(|s| !s.is_empty()) {
        state.db.with_conn(|conn| {
            conn.execute(
                "UPDATE career_path_benefit
                 SET path_entry_id = ?1, title = ?2, is_active = ?3, notes = ?4
                 WHERE id = ?5",
                rusqlite::params![input.path_entry_id, title, is_active, notes, existing],
            )?;
            Ok(())
        })?;
        existing
    } else {
        let id = Uuid::new_v4().to_string();
        state.db.with_conn(|conn| {
            let sort: i64 = conn
                .query_row(
                    "SELECT COALESCE(MAX(sort_order), 0) + 1 FROM career_path_benefit
                     WHERE path_entry_id = ?1",
                    rusqlite::params![input.path_entry_id],
                    |r| r.get(0),
                )
                .unwrap_or(1);
            conn.execute(
                "INSERT INTO career_path_benefit
                 (id, path_entry_id, title, is_active, notes, sort_order)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
                rusqlite::params![id, input.path_entry_id, title, is_active, notes, sort],
            )?;
            Ok(())
        })?;
        id
    };
    bump_career(&app, &state)?;
    Ok(id)
}

#[tauri::command]
pub fn career_delete_path_benefit(
    app: AppHandle,
    state: State<'_, AppState>,
    id: String,
) -> CmdResult<()> {
    state.db.with_conn(|conn| {
        conn.execute(
            "DELETE FROM career_path_benefit WHERE id = ?1",
            rusqlite::params![id],
        )?;
        Ok(())
    })?;
    bump_career(&app, &state)?;
    Ok(())
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PathCompensationDto {
    pub id: String,
    pub path_entry_id: String,
    pub kind: String,
    pub title: String,
    pub amount: Option<f64>,
    pub currency: String,
    pub cadence: String,
    pub notes: String,
    pub sort_order: i64,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UpsertPathCompensationInput {
    pub id: Option<String>,
    pub path_entry_id: String,
    pub kind: Option<String>,
    pub title: String,
    pub amount: Option<f64>,
    pub currency: Option<String>,
    pub cadence: Option<String>,
    pub notes: Option<String>,
}

fn normalize_compensation_kind(kind: Option<String>) -> String {
    match kind.as_deref().map(|s| s.trim().to_ascii_lowercase()).as_deref() {
        Some("bonus") => "bonus".into(),
        Some("equity") => "equity".into(),
        Some("stipend") => "stipend".into(),
        Some("other") => "other".into(),
        _ => "base_salary".into(),
    }
}

fn normalize_compensation_cadence(cadence: Option<String>) -> String {
    match cadence.as_deref().map(|s| s.trim().to_ascii_lowercase()).as_deref() {
        Some("monthly") => "monthly".into(),
        Some("one_time") | Some("onetime") | Some("one-time") => "one_time".into(),
        _ => "yearly".into(),
    }
}

#[tauri::command]
pub fn career_list_path_compensation(
    state: State<'_, AppState>,
    path_entry_id: String,
) -> CmdResult<Vec<PathCompensationDto>> {
    state
        .db
        .with_conn(|conn| {
            let mut stmt = conn.prepare(
                "SELECT id, path_entry_id, kind, title, amount, currency, cadence, notes, sort_order
                 FROM career_path_compensation
                 WHERE path_entry_id = ?1
                 ORDER BY sort_order ASC, title ASC
                 LIMIT 200",
            )?;
            let rows = stmt
                .query_map(rusqlite::params![path_entry_id], |r| {
                    Ok(PathCompensationDto {
                        id: r.get(0)?,
                        path_entry_id: r.get(1)?,
                        kind: r.get(2)?,
                        title: r.get(3)?,
                        amount: r.get(4)?,
                        currency: r.get(5)?,
                        cadence: r.get(6)?,
                        notes: r.get(7)?,
                        sort_order: r.get(8)?,
                    })
                })?
                .collect::<Result<Vec<_>, _>>()?;
            Ok(rows)
        })
        .map_err(Into::into)
}

#[tauri::command]
pub fn career_upsert_path_compensation(
    app: AppHandle,
    state: State<'_, AppState>,
    input: UpsertPathCompensationInput,
) -> CmdResult<String> {
    let title = input.title.trim();
    if title.is_empty() {
        return Err(anyhow::anyhow!("title is required").into());
    }
    let kind = normalize_compensation_kind(input.kind);
    let cadence = normalize_compensation_cadence(input.cadence);
    let currency = input
        .currency
        .map(|s| s.trim().to_uppercase())
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| "USD".into());
    let notes = input.notes.unwrap_or_default();
    let id = if let Some(existing) = input.id.filter(|s| !s.is_empty()) {
        state.db.with_conn(|conn| {
            conn.execute(
                "UPDATE career_path_compensation
                 SET path_entry_id = ?1, kind = ?2, title = ?3, amount = ?4,
                     currency = ?5, cadence = ?6, notes = ?7
                 WHERE id = ?8",
                rusqlite::params![
                    input.path_entry_id,
                    kind,
                    title,
                    input.amount,
                    currency,
                    cadence,
                    notes,
                    existing
                ],
            )?;
            Ok(())
        })?;
        existing
    } else {
        let id = Uuid::new_v4().to_string();
        state.db.with_conn(|conn| {
            let sort: i64 = conn
                .query_row(
                    "SELECT COALESCE(MAX(sort_order), 0) + 1 FROM career_path_compensation
                     WHERE path_entry_id = ?1",
                    rusqlite::params![input.path_entry_id],
                    |r| r.get(0),
                )
                .unwrap_or(1);
            conn.execute(
                "INSERT INTO career_path_compensation
                 (id, path_entry_id, kind, title, amount, currency, cadence, notes, sort_order)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)",
                rusqlite::params![
                    id,
                    input.path_entry_id,
                    kind,
                    title,
                    input.amount,
                    currency,
                    cadence,
                    notes,
                    sort
                ],
            )?;
            Ok(())
        })?;
        id
    };
    bump_career(&app, &state)?;
    Ok(id)
}

#[tauri::command]
pub fn career_delete_path_compensation(
    app: AppHandle,
    state: State<'_, AppState>,
    id: String,
) -> CmdResult<()> {
    state.db.with_conn(|conn| {
        conn.execute(
            "DELETE FROM career_path_compensation WHERE id = ?1",
            rusqlite::params![id],
        )?;
        Ok(())
    })?;
    bump_career(&app, &state)?;
    Ok(())
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PathEmploymentTermsDto {
    pub path_entry_id: String,
    pub employment_type: String,
    pub work_location: String,
    pub schedule_notes: String,
    pub notice_period: String,
    pub other_terms: String,
    pub updated_at: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UpsertPathEmploymentTermsInput {
    pub path_entry_id: String,
    pub employment_type: Option<String>,
    pub work_location: Option<String>,
    pub schedule_notes: Option<String>,
    pub notice_period: Option<String>,
    pub other_terms: Option<String>,
}

#[tauri::command]
pub fn career_get_path_employment_terms(
    state: State<'_, AppState>,
    path_entry_id: String,
) -> CmdResult<PathEmploymentTermsDto> {
    state
        .db
        .with_conn(|conn| {
            let mut stmt = conn.prepare(
                "SELECT path_entry_id, employment_type, work_location, schedule_notes,
                        notice_period, other_terms, updated_at
                 FROM career_path_employment_terms
                 WHERE path_entry_id = ?1",
            )?;
            let mut rows = stmt.query(rusqlite::params![path_entry_id])?;
            if let Some(r) = rows.next()? {
                Ok(PathEmploymentTermsDto {
                    path_entry_id: r.get(0)?,
                    employment_type: r.get(1)?,
                    work_location: r.get(2)?,
                    schedule_notes: r.get(3)?,
                    notice_period: r.get(4)?,
                    other_terms: r.get(5)?,
                    updated_at: r.get(6)?,
                })
            } else {
                Ok(PathEmploymentTermsDto {
                    path_entry_id,
                    employment_type: String::new(),
                    work_location: String::new(),
                    schedule_notes: String::new(),
                    notice_period: String::new(),
                    other_terms: String::new(),
                    updated_at: None,
                })
            }
        })
        .map_err(Into::into)
}

#[tauri::command]
pub fn career_upsert_path_employment_terms(
    app: AppHandle,
    state: State<'_, AppState>,
    input: UpsertPathEmploymentTermsInput,
) -> CmdResult<()> {
    let now = Utc::now().to_rfc3339();
    state.db.with_conn(|conn| {
        conn.execute(
            "INSERT INTO career_path_employment_terms
             (path_entry_id, employment_type, work_location, schedule_notes,
              notice_period, other_terms, updated_at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
             ON CONFLICT(path_entry_id) DO UPDATE SET
               employment_type = excluded.employment_type,
               work_location = excluded.work_location,
               schedule_notes = excluded.schedule_notes,
               notice_period = excluded.notice_period,
               other_terms = excluded.other_terms,
               updated_at = excluded.updated_at",
            rusqlite::params![
                input.path_entry_id,
                input.employment_type.unwrap_or_default(),
                input.work_location.unwrap_or_default(),
                input.schedule_notes.unwrap_or_default(),
                input.notice_period.unwrap_or_default(),
                input.other_terms.unwrap_or_default(),
                now
            ],
        )?;
        Ok(())
    })?;
    bump_career(&app, &state)?;
    Ok(())
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CareerSkillDto {
    pub id: String,
    pub name: String,
    pub evidence_count: i64,
    pub sort_order: i64,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UpsertCareerSkillInput {
    pub id: Option<String>,
    pub name: String,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AddSkillEvidenceInput {
    pub skill_id: String,
    pub path_entry_id: Option<String>,
    pub note: Option<String>,
}

#[tauri::command]
pub fn career_list_skills(state: State<'_, AppState>) -> CmdResult<Vec<CareerSkillDto>> {
    state
        .db
        .with_conn(|conn| {
            let mut stmt = conn.prepare(
                "SELECT s.id, s.name, s.sort_order,
                        (SELECT COUNT(*) FROM career_skill_evidence e WHERE e.skill_id = s.id)
                 FROM career_skill s
                 ORDER BY s.sort_order ASC, s.name ASC
                 LIMIT 200",
            )?;
            let rows = stmt
                .query_map([], |r| {
                    Ok(CareerSkillDto {
                        id: r.get(0)?,
                        name: r.get(1)?,
                        sort_order: r.get(2)?,
                        evidence_count: r.get(3)?,
                    })
                })?
                .collect::<Result<Vec<_>, _>>()?;
            Ok(rows)
        })
        .map_err(Into::into)
}

#[tauri::command]
pub fn career_upsert_skill(
    app: AppHandle,
    state: State<'_, AppState>,
    input: UpsertCareerSkillInput,
) -> CmdResult<String> {
    let name = input.name.trim();
    if name.is_empty() {
        return Err(anyhow::anyhow!("name is required").into());
    }
    let id = if let Some(existing) = input.id.filter(|s| !s.is_empty()) {
        state.db.with_conn(|conn| {
            conn.execute(
                "UPDATE career_skill SET name = ?1 WHERE id = ?2",
                rusqlite::params![name, existing],
            )?;
            Ok(())
        })?;
        existing
    } else {
        let id = Uuid::new_v4().to_string();
        state.db.with_conn(|conn| {
            let sort: i64 = conn
                .query_row(
                    "SELECT COALESCE(MAX(sort_order), 0) + 1 FROM career_skill",
                    [],
                    |r| r.get(0),
                )
                .unwrap_or(1);
            conn.execute(
                "INSERT INTO career_skill (id, name, sort_order) VALUES (?1, ?2, ?3)",
                rusqlite::params![id, name, sort],
            )?;
            Ok(())
        })?;
        id
    };
    bump_career(&app, &state)?;
    Ok(id)
}

#[tauri::command]
pub fn career_delete_skill(
    app: AppHandle,
    state: State<'_, AppState>,
    id: String,
) -> CmdResult<()> {
    state.db.with_conn(|conn| {
        conn.execute("DELETE FROM career_skill WHERE id = ?1", rusqlite::params![id])?;
        Ok(())
    })?;
    bump_career(&app, &state)?;
    Ok(())
}

#[tauri::command]
pub fn career_add_skill_evidence(
    app: AppHandle,
    state: State<'_, AppState>,
    input: AddSkillEvidenceInput,
) -> CmdResult<String> {
    let id = Uuid::new_v4().to_string();
    let now = Utc::now().to_rfc3339();
    let note = input.note.unwrap_or_default();
    state.db.with_conn(|conn| {
        conn.execute(
            "INSERT INTO career_skill_evidence (id, skill_id, path_entry_id, note, created_at)
             VALUES (?1, ?2, ?3, ?4, ?5)",
            rusqlite::params![id, input.skill_id, input.path_entry_id, note, now],
        )?;
        Ok(())
    })?;
    bump_career(&app, &state)?;
    Ok(id)
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AchievementPipelineDto {
    pub open_roadmap_items: i64,
    pub done_milestones: i64,
    pub brag_wins: i64,
    pub active_benefits: i64,
    pub promotions: i64,
    pub people: i64,
    pub compensation_items: i64,
}

#[tauri::command]
pub fn career_path_achievement_pipeline(
    state: State<'_, AppState>,
    path_entry_id: String,
) -> CmdResult<AchievementPipelineDto> {
    state
        .db
        .with_conn(|conn| {
            let open_roadmap_items: i64 = conn.query_row(
                "SELECT COUNT(*) FROM career_path_milestone
                 WHERE path_entry_id = ?1 AND status != 'done'",
                rusqlite::params![path_entry_id],
                |r| r.get(0),
            )?;
            let done_milestones: i64 = conn.query_row(
                "SELECT COUNT(*) FROM career_path_milestone
                 WHERE path_entry_id = ?1 AND status = 'done'",
                rusqlite::params![path_entry_id],
                |r| r.get(0),
            )?;
            let brag_wins: i64 = conn
                .query_row("SELECT COUNT(*) FROM career_brag_entry", [], |r| r.get(0))
                .unwrap_or(0);
            let active_benefits: i64 = conn.query_row(
                "SELECT COUNT(*) FROM career_path_benefit
                 WHERE path_entry_id = ?1 AND is_active = 1",
                rusqlite::params![path_entry_id],
                |r| r.get(0),
            )?;
            let promotions: i64 = conn.query_row(
                "SELECT COUNT(*) FROM career_path_promotion WHERE path_entry_id = ?1",
                rusqlite::params![path_entry_id],
                |r| r.get(0),
            )?;
            let people: i64 = conn.query_row(
                "SELECT COUNT(*) FROM career_path_person WHERE path_entry_id = ?1",
                rusqlite::params![path_entry_id],
                |r| r.get(0),
            )?;
            let compensation_items: i64 = conn
                .query_row(
                    "SELECT COUNT(*) FROM career_path_compensation WHERE path_entry_id = ?1",
                    rusqlite::params![path_entry_id],
                    |r| r.get(0),
                )
                .unwrap_or(0);
            Ok(AchievementPipelineDto {
                open_roadmap_items,
                done_milestones,
                brag_wins,
                active_benefits,
                promotions,
                people,
                compensation_items,
            })
        })
        .map_err(Into::into)
}

// MARK: - Phase C depth: role expectations, relationships, resume, merge

#[derive(Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RoleExpectationBoxDto {
    pub id: String,
    pub title: String,
    pub body: String,
    #[serde(default)]
    pub sort_order: i64,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RoleExpectationDto {
    pub path_entry_id: String,
    pub summary: String,
    pub boxes: Vec<RoleExpectationBoxDto>,
    pub updated_at: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SaveRoleExpectationInput {
    pub path_entry_id: String,
    pub summary: Option<String>,
    pub boxes: Option<Vec<RoleExpectationBoxDto>>,
}

#[tauri::command]
pub fn career_get_role_expectation(
    state: State<'_, AppState>,
    path_entry_id: String,
) -> CmdResult<RoleExpectationDto> {
    state
        .db
        .with_conn(|conn| {
            let mut stmt = conn.prepare(
                "SELECT path_entry_id, summary, boxes_json, updated_at
                 FROM career_path_role_expectation WHERE path_entry_id = ?1",
            )?;
            let row = stmt
                .query_row(rusqlite::params![path_entry_id], |r| {
                    let boxes_json: String = r.get(2)?;
                    let boxes: Vec<RoleExpectationBoxDto> =
                        serde_json::from_str(&boxes_json).unwrap_or_default();
                    Ok(RoleExpectationDto {
                        path_entry_id: r.get(0)?,
                        summary: r.get(1)?,
                        boxes,
                        updated_at: r.get(3)?,
                    })
                })
                .optional()?;
            Ok(row.unwrap_or(RoleExpectationDto {
                path_entry_id,
                summary: String::new(),
                boxes: Vec::new(),
                updated_at: None,
            }))
        })
        .map_err(Into::into)
}

#[tauri::command]
pub fn career_save_role_expectation(
    app: AppHandle,
    state: State<'_, AppState>,
    input: SaveRoleExpectationInput,
) -> CmdResult<()> {
    let summary = input.summary.unwrap_or_default();
    let boxes = input.boxes.unwrap_or_default();
    let boxes_json = serde_json::to_string(&boxes).unwrap_or_else(|_| "[]".into());
    let now = Utc::now().to_rfc3339();
    state.db.with_conn(|conn| {
        let existing: Option<String> = conn
            .query_row(
                "SELECT id FROM career_path_role_expectation WHERE path_entry_id = ?1",
                rusqlite::params![input.path_entry_id],
                |r| r.get(0),
            )
            .optional()?;
        if let Some(id) = existing {
            conn.execute(
                "UPDATE career_path_role_expectation
                 SET summary = ?1, boxes_json = ?2, updated_at = ?3
                 WHERE id = ?4",
                rusqlite::params![summary, boxes_json, now, id],
            )?;
        } else {
            let id = Uuid::new_v4().to_string();
            conn.execute(
                "INSERT INTO career_path_role_expectation
                 (id, path_entry_id, summary, boxes_json, updated_at)
                 VALUES (?1, ?2, ?3, ?4, ?5)",
                rusqlite::params![id, input.path_entry_id, summary, boxes_json, now],
            )?;
        }
        Ok(())
    })?;
    bump_career(&app, &state)?;
    Ok(())
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PathRelationshipDto {
    pub id: String,
    pub from_entry_id: String,
    pub to_entry_id: String,
    pub kind: String,
    pub notes: String,
    pub created_at: String,
    pub linked_entry_id: String,
    pub linked_organization: String,
    pub linked_role_title: String,
    pub direction: String,
}

#[tauri::command]
pub fn career_list_path_relationships(
    state: State<'_, AppState>,
    path_entry_id: String,
) -> CmdResult<Vec<PathRelationshipDto>> {
    state
        .db
        .with_conn(|conn| {
            let mut stmt = conn.prepare(
                "SELECT r.id, r.from_entry_id, r.to_entry_id, r.kind, r.notes, r.created_at,
                        e.organization, e.role_title
                 FROM career_path_relationship r
                 JOIN career_path_entry e ON e.id = CASE
                   WHEN r.from_entry_id = ?1 THEN r.to_entry_id
                   ELSE r.from_entry_id
                 END
                 WHERE r.from_entry_id = ?1 OR r.to_entry_id = ?1
                 ORDER BY r.created_at DESC",
            )?;
            let rows = stmt
                .query_map(rusqlite::params![path_entry_id], |r| {
                    let from_id: String = r.get(1)?;
                    let to_id: String = r.get(2)?;
                    let linked_entry_id = if from_id == path_entry_id {
                        to_id.clone()
                    } else {
                        from_id.clone()
                    };
                    let direction = if from_id == path_entry_id {
                        "outgoing".to_string()
                    } else {
                        "incoming".to_string()
                    };
                    Ok(PathRelationshipDto {
                        id: r.get(0)?,
                        from_entry_id: from_id,
                        to_entry_id: to_id,
                        kind: r.get(3)?,
                        notes: r.get(4)?,
                        created_at: r.get(5)?,
                        linked_organization: r.get(6)?,
                        linked_role_title: r.get(7)?,
                        linked_entry_id,
                        direction,
                    })
                })?
                .collect::<Result<Vec<_>, _>>()?;
            Ok(rows)
        })
        .map_err(Into::into)
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UpsertPathRelationshipInput {
    pub id: Option<String>,
    pub from_entry_id: String,
    pub to_entry_id: String,
    pub kind: Option<String>,
    pub notes: Option<String>,
}

#[tauri::command]
pub fn career_upsert_path_relationship(
    app: AppHandle,
    state: State<'_, AppState>,
    input: UpsertPathRelationshipInput,
) -> CmdResult<String> {
    if input.from_entry_id == input.to_entry_id {
        return Err(anyhow::anyhow!("Cannot link an entry to itself").into());
    }
    let kind = input
        .kind
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| "related".to_string());
    let notes = input.notes.unwrap_or_default();
    let now = Utc::now().to_rfc3339();
    let id = if let Some(existing) = input.id.filter(|s| !s.is_empty()) {
        state.db.with_conn(|conn| {
            conn.execute(
                "UPDATE career_path_relationship
                 SET from_entry_id = ?1, to_entry_id = ?2, kind = ?3, notes = ?4
                 WHERE id = ?5",
                rusqlite::params![
                    input.from_entry_id,
                    input.to_entry_id,
                    kind,
                    notes,
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
                "INSERT INTO career_path_relationship
                 (id, from_entry_id, to_entry_id, kind, notes, created_at)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6)
                 ON CONFLICT(from_entry_id, to_entry_id, kind) DO UPDATE SET
                   notes = excluded.notes",
                rusqlite::params![
                    id,
                    input.from_entry_id,
                    input.to_entry_id,
                    kind,
                    notes,
                    now
                ],
            )?;
            Ok(())
        })?;
        id
    };
    bump_career(&app, &state)?;
    Ok(id)
}

#[tauri::command]
pub fn career_delete_path_relationship(
    app: AppHandle,
    state: State<'_, AppState>,
    id: String,
) -> CmdResult<()> {
    state.db.with_conn(|conn| {
        conn.execute(
            "DELETE FROM career_path_relationship WHERE id = ?1",
            rusqlite::params![id],
        )?;
        Ok(())
    })?;
    bump_career(&app, &state)?;
    Ok(())
}

#[tauri::command]
pub fn career_set_path_resume(
    app: AppHandle,
    state: State<'_, AppState>,
    path_entry_id: String,
    resume_document_id: Option<String>,
) -> CmdResult<()> {
    state.db.with_conn(|conn| {
        conn.execute(
            "UPDATE career_path_entry SET resume_document_id = ?1 WHERE id = ?2",
            rusqlite::params![resume_document_id, path_entry_id],
        )?;
        Ok(())
    })?;
    bump_career(&app, &state)?;
    Ok(())
}

#[tauri::command]
pub fn career_merge_path_entries(
    app: AppHandle,
    state: State<'_, AppState>,
    from_id: String,
    to_id: String,
) -> CmdResult<()> {
    if from_id == to_id {
        return Err(anyhow::anyhow!("Source and target must differ").into());
    }
    let now = Utc::now().to_rfc3339();
    state.db.with_conn(|conn| {
        let tx = conn.unchecked_transaction()?;

        let milestone_base: i64 = tx.query_row(
            "SELECT COALESCE(MAX(sort_order), 0) FROM career_path_milestone WHERE path_entry_id = ?1",
            rusqlite::params![to_id],
            |r| r.get(0),
        )?;
        tx.execute(
            "UPDATE career_path_milestone
             SET path_entry_id = ?1,
                 sort_order = sort_order + ?2
             WHERE path_entry_id = ?3",
            rusqlite::params![to_id, milestone_base, from_id],
        )?;

        let journal_base: i64 = tx.query_row(
            "SELECT COALESCE(MAX(sort_order), 0) FROM career_path_journal_entry WHERE path_entry_id = ?1",
            rusqlite::params![to_id],
            |r| r.get(0),
        )?;
        tx.execute(
            "UPDATE career_path_journal_entry
             SET path_entry_id = ?1,
                 sort_order = sort_order + ?2
             WHERE path_entry_id = ?3",
            rusqlite::params![to_id, journal_base, from_id],
        )?;

        // Rewire relationships involving the source; drop rows that would violate uniqueness.
        tx.execute(
            "DELETE FROM career_path_relationship
             WHERE from_entry_id = ?1 AND to_entry_id = ?2",
            rusqlite::params![from_id, to_id],
        )?;
        tx.execute(
            "UPDATE career_path_relationship SET from_entry_id = ?1
             WHERE from_entry_id = ?2 AND to_entry_id != ?1",
            rusqlite::params![to_id, from_id],
        )?;
        tx.execute(
            "UPDATE career_path_relationship SET to_entry_id = ?1
             WHERE to_entry_id = ?2 AND from_entry_id != ?1",
            rusqlite::params![to_id, from_id],
        )?;
        tx.execute(
            "DELETE FROM career_path_relationship WHERE from_entry_id = to_entry_id",
            [],
        )?;

        let merge_id = Uuid::new_v4().to_string();
        tx.execute(
            "INSERT OR IGNORE INTO career_path_relationship
             (id, from_entry_id, to_entry_id, kind, notes, created_at)
             VALUES (?1, ?2, ?3, 'merged', '', ?4)",
            rusqlite::params![merge_id, from_id, to_id, now],
        )?;

        tx.execute(
            "DELETE FROM career_path_entry WHERE id = ?1",
            rusqlite::params![from_id],
        )?;

        tx.commit()?;
        Ok(())
    })?;
    bump_career(&app, &state)?;
    Ok(())
}

/// Write Typst source to a sibling `.typ` file and compile to PDF via the `typst` CLI on PATH.
#[tauri::command]
pub fn career_compile_typst_pdf(source: String, pdf_path: String) -> CmdResult<()> {
    use std::fs;
    use std::io::ErrorKind;
    use std::path::Path;
    use std::process::Command;

    let pdf_path = pdf_path.trim();
    if pdf_path.is_empty() {
        return Err(anyhow::anyhow!("pdf_path is required").into());
    }

    let pdf = Path::new(pdf_path);
    if let Some(parent) = pdf.parent() {
        if !parent.as_os_str().is_empty() {
            fs::create_dir_all(parent)
                .map_err(|e| anyhow::anyhow!("Failed to create output directory: {e}"))?;
        }
    }

    let typ_path = pdf.with_extension("typ");
    fs::write(&typ_path, &source)
        .map_err(|e| anyhow::anyhow!("Failed to write Typst source: {e}"))?;

    let typ_arg = typ_path
        .to_str()
        .ok_or_else(|| anyhow::anyhow!("Typst source path is not valid UTF-8"))?;

    let output = Command::new("typst")
        .args(["compile", typ_arg, pdf_path])
        .output();

    match output {
        Err(e) if e.kind() == ErrorKind::NotFound => Err(anyhow::anyhow!(
            "typst not found on PATH. Install Typst from https://typst.app"
        )
        .into()),
        Err(e) => Err(anyhow::anyhow!("Failed to run typst: {e}").into()),
        Ok(out) if !out.status.success() => {
            let stderr = String::from_utf8_lossy(&out.stderr);
            let stdout = String::from_utf8_lossy(&out.stdout);
            let detail = if !stderr.trim().is_empty() {
                stderr.trim().to_string()
            } else {
                stdout.trim().to_string()
            };
            let message = if detail.is_empty() {
                "typst compile failed".to_string()
            } else {
                format!("typst compile failed: {detail}")
            };
            Err(anyhow::anyhow!(message).into())
        }
        Ok(_) => Ok(()),
    }
}
