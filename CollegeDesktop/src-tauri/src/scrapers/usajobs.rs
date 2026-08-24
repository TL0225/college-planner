//! USAJobs Search API (official JSON — not HTML scraping). Swift `USAJobsScraper` parity.

use crate::scrapers::{JobBoardSyncSourceResult, ScrapedJobListing};
use crate::AppState;
use anyhow::{Context, Result};
use serde::Deserialize;

const RESULTS_PER_PAGE: usize = 100;
const MAX_PAGES: usize = 5;
const MAX_LISTINGS: usize = 80;

#[derive(Debug, Deserialize)]
struct UsaJobsSearchResponse {
    #[serde(rename = "SearchResult")]
    search_result: Option<UsaJobsSearchResult>,
}

#[derive(Debug, Deserialize)]
struct UsaJobsSearchResult {
    #[serde(rename = "SearchResultItems")]
    search_result_items: Option<Vec<UsaJobsSearchItem>>,
}

#[derive(Debug, Deserialize)]
struct UsaJobsSearchItem {
    #[serde(rename = "MatchedObjectDescriptor")]
    matched_object_descriptor: UsaJobsPositionDescriptor,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "PascalCase")]
struct UsaJobsPositionDescriptor {
    position_id: Option<String>,
    position_title: Option<String>,
    position_uri: Option<String>,
    #[serde(rename = "ApplyURI")]
    apply_uri: Option<Vec<String>>,
    position_location_display: Option<String>,
    publication_start_date: Option<String>,
}

fn read_credentials(state: &AppState) -> Result<(String, String)> {
    state
        .db
        .with_conn(|conn| {
            let api_key: Option<String> = conn
                .query_row(
                    "SELECT value FROM app_settings WHERE key = 'jobBoard.usajobs.apiKey' LIMIT 1",
                    [],
                    |r| r.get(0),
                )
                .ok();
            let email: Option<String> = conn
                .query_row(
                    "SELECT value FROM app_settings WHERE key = 'jobBoard.usajobs.userEmail' LIMIT 1",
                    [],
                    |r| r.get(0),
                )
                .ok();
            match (api_key, email) {
                (Some(k), Some(e)) if !k.trim().is_empty() && !e.trim().is_empty() => {
                    Ok((k.trim().to_string(), e.trim().to_string()))
                }
                _ => anyhow::bail!("USAJobs API key and email are required (Settings → Career)"),
            }
        })
        .map_err(|e| anyhow::anyhow!("{e}"))
}

fn map_listing(item: &UsaJobsSearchItem) -> Option<ScrapedJobListing> {
    let descriptor = &item.matched_object_descriptor;
    let position_id = descriptor.position_id.as_deref()?.trim();
    if position_id.is_empty() {
        return None;
    }
    let title = descriptor
        .position_title
        .as_deref()
        .filter(|s| !s.trim().is_empty())
        .unwrap_or("Federal job");
    let url = descriptor
        .apply_uri
        .as_ref()
        .and_then(|uris| uris.first())
        .or(descriptor.position_uri.as_ref())
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| format!("https://www.usajobs.gov/GetJob/ViewDetails/{position_id}"));
    Some(ScrapedJobListing {
        external_id: position_id.to_string(),
        external_path: format!("/GetJob/ViewDetails/{position_id}"),
        title: title.to_string(),
        location: descriptor
            .position_location_display
            .clone()
            .unwrap_or_default(),
        url,
        posted_at: descriptor.publication_start_date.clone(),
        source: "usajobs".to_string(),
    })
}

async fn fetch_page(api_key: &str, email: &str, page: usize) -> Result<UsaJobsSearchResponse> {
    let client = reqwest::Client::builder()
        .timeout(std::time::Duration::from_secs(25))
        .build()?;
    let response = client
        .get("https://data.usajobs.gov/api/search")
        .query(&[
            ("Page", page.to_string()),
            ("ResultsPerPage", RESULTS_PER_PAGE.to_string()),
        ])
        .header("Host", "data.usajobs.gov")
        .header("User-Agent", email)
        .header("Authorization-Key", api_key)
        .header("Accept", "application/json")
        .send()
        .await
        .context("USAJobs API request failed")?;

    let status = response.status();
    if status.as_u16() == 401 {
        anyhow::bail!("USAJobs rejected credentials — check API key and email");
    }
    if status.as_u16() == 429 {
        anyhow::bail!("USAJobs rate limited — try again later");
    }
    if !status.is_success() {
        anyhow::bail!("USAJobs HTTP {}", status);
    }

    response
        .json::<UsaJobsSearchResponse>()
        .await
        .context("USAJobs JSON decode failed")
}

pub async fn sync_listings(
    state: &AppState,
) -> Result<(JobBoardSyncSourceResult, Vec<ScrapedJobListing>)> {
    let (api_key, email) = read_credentials(state)?;
    let mut page = 1usize;
    let mut all = Vec::new();
    let mut seen = std::collections::HashSet::new();

    while page <= MAX_PAGES && all.len() < MAX_LISTINGS {
        let response = fetch_page(&api_key, &email, page).await?;
        let items = response
            .search_result
            .and_then(|r| r.search_result_items)
            .unwrap_or_default();
        if items.is_empty() {
            break;
        }
        let mut added = 0usize;
        for item in &items {
            let Some(listing) = map_listing(item) else {
                continue;
            };
            if seen.insert(listing.external_id.clone()) {
                all.push(listing);
                added += 1;
                if all.len() >= MAX_LISTINGS {
                    break;
                }
            }
        }
        if added == 0 || items.len() < RESULTS_PER_PAGE {
            break;
        }
        page += 1;
    }

    Ok((
        JobBoardSyncSourceResult {
            source: "usajobs".to_string(),
            label: "USAJobs".to_string(),
            imported: 0,
            updated: 0,
            skipped: 0,
            fetched: all.len() as i64,
            error: None,
        },
        all,
    ))
}
