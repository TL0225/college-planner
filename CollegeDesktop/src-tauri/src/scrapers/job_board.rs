//! Public job-board hub scrapers (RemoteOK, Jobicy, Y Combinator).
//! Mirrors Swift `JobBoardPublicHubScrapeEngine` heuristics.

use crate::scrapers::fetch_html;
use anyhow::{Context, Result};
use regex::Regex;
use serde::{Deserialize, Serialize};
use std::collections::HashSet;

const MAX_LIST_PAGES: usize = 5;
const MAX_LISTINGS: usize = 80;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum JobBoardSource {
    RemoteOk,
    Jobicy,
    YCombinator,
    BuiltIn,
    UsaJobs,
}

impl JobBoardSource {
    pub fn id(self) -> &'static str {
        match self {
            Self::RemoteOk => "remote_ok",
            Self::Jobicy => "jobicy",
            Self::YCombinator => "y_combinator",
            Self::BuiltIn => "built_in",
            Self::UsaJobs => "usajobs",
        }
    }

    pub fn label(self) -> &'static str {
        match self {
            Self::RemoteOk => "RemoteOK",
            Self::Jobicy => "Jobicy",
            Self::YCombinator => "Y Combinator",
            Self::BuiltIn => "Built In",
            Self::UsaJobs => "USAJobs",
        }
    }

    pub fn default_hub_url(self) -> &'static str {
        match self {
            Self::RemoteOk => "https://remoteok.com/remote-jobs",
            Self::Jobicy => "https://jobicy.com/remote-jobs",
            Self::YCombinator => "https://www.ycombinator.com/jobs",
            Self::BuiltIn => "https://builtin.com/jobs",
            Self::UsaJobs => "https://www.usajobs.gov/Search/Results",
        }
    }

    pub fn company_name(self) -> &'static str {
        self.label()
    }

    fn list_link_pattern(self) -> &'static str {
        match self {
            Self::RemoteOk => r#"href="(/remote-jobs/\d+[^"]*)""#,
            Self::Jobicy => {
                r#"href="(https?://jobicy\.com/jobs/\d+[^"]*|/jobs/\d+[^"]*)""#
            }
            Self::YCombinator => r#"href="(/companies/[^"]+/jobs/[^"]+)""#,
            Self::BuiltIn => r#"href="(/job/[^"]+|https?://builtin\.com/job/[^"]+)""#,
            Self::UsaJobs => r#"href="(/GetJob/[^"]+)""#,
        }
    }

    fn listing_page_url(self, base: &str, page: usize) -> String {
        let trimmed = base.trim_end_matches('/');
        if page <= 1 {
            return trimmed.to_string();
        }
        format!("{trimmed}?page={page}")
    }

    fn validate_hub_url(self, url: &str) -> bool {
        let lower = url.to_lowercase();
        match self {
            Self::RemoteOk => lower.contains("remoteok.com"),
            Self::Jobicy => {
                lower.contains("jobicy.com")
                    && (lower.contains("/remote-jobs") || lower.contains("/jobs"))
            }
            Self::YCombinator => lower.contains("ycombinator.com") && lower.contains("/jobs"),
            Self::BuiltIn => lower.contains("builtin.com") && lower.contains("/job"),
            Self::UsaJobs => lower.contains("usajobs.gov"),
        }
    }
}

impl std::str::FromStr for JobBoardSource {
    type Err = anyhow::Error;

    fn from_str(s: &str) -> Result<Self> {
        match s.trim().to_ascii_lowercase().replace('-', "_").as_str() {
            "remote_ok" | "remoteok" => Ok(Self::RemoteOk),
            "jobicy" => Ok(Self::Jobicy),
            "y_combinator" | "ycombinator" | "yc" => Ok(Self::YCombinator),
            "built_in" | "builtin" => Ok(Self::BuiltIn),
            "usajobs" | "usa_jobs" => Ok(Self::UsaJobs),
            other => anyhow::bail!("unknown job board source: {other}"),
        }
    }
}

pub fn all_sources() -> [JobBoardSource; 5] {
    [
        JobBoardSource::RemoteOk,
        JobBoardSource::Jobicy,
        JobBoardSource::YCombinator,
        JobBoardSource::BuiltIn,
        JobBoardSource::UsaJobs,
    ]
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ScrapedJobListing {
    pub external_id: String,
    pub external_path: String,
    pub title: String,
    pub location: String,
    pub url: String,
    pub posted_at: Option<String>,
    pub source: String,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct JobBoardSyncSourceResult {
    pub source: String,
    pub label: String,
    pub imported: i64,
    pub updated: i64,
    pub skipped: i64,
    pub fetched: i64,
    pub error: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct JobBoardSyncResult {
    pub imported: i64,
    pub updated: i64,
    pub skipped: i64,
    pub fetched: i64,
    pub sources: Vec<JobBoardSyncSourceResult>,
}

fn is_cloudflare_block(html: &str, status: u16) -> bool {
    if status == 403 {
        return true;
    }
    let lower = html.to_lowercase();
    lower.contains("cf-browser-verification")
        || lower.contains("just a moment...")
        || (lower.contains("cloudflare") && lower.contains("challenge-platform"))
}

fn absolute_url(href: &str, base: &str) -> Option<String> {
    if href.starts_with("http://") || href.starts_with("https://") {
        return Some(href.to_string());
    }
    if href.starts_with("//") {
        return Some(format!("https:{href}"));
    }
    if href.starts_with('/') {
        let host = base
            .trim_start_matches("https://")
            .trim_start_matches("http://")
            .split('/')
            .next()
            .unwrap_or("");
        if host.is_empty() {
            return None;
        }
        return Some(format!("https://{host}{href}"));
    }
    let base_trimmed = base.trim_end_matches('/');
    Some(format!("{base_trimmed}/{href}"))
}

fn path_from_url(url: &str) -> String {
    url.trim_start_matches("https://")
        .trim_start_matches("http://")
        .split_once('/')
        .map(|(_, path)| format!("/{path}"))
        .unwrap_or_else(|| url.to_string())
}

fn extract_link_title(html: &str, href: &str) -> Option<String> {
    let fragment = href.split('/').next_back().unwrap_or(href);
    let pattern = format!(
        r#"href="[^"]*{}[^"]*"[^>]*>([^<]+)<"#,
        regex::escape(fragment)
    );
    let re = Regex::new(&pattern).ok()?;
    let cap = re.captures(html)?;
    let title = cap.get(1)?.as_str().trim();
    if title.is_empty() {
        None
    } else {
        Some(title.to_string())
    }
}

fn extract_nearby_location(html: &str, href: &str) -> Option<String> {
    let pos = html.find(href)?;
    let start = pos.saturating_sub(120);
    let end = (pos + href.len() + 120).min(html.len());
    let snippet = html[start..end].to_ascii_lowercase();
    if snippet.contains("remote") {
        Some("Remote".into())
    } else if snippet.contains("hybrid") {
        Some("Hybrid".into())
    } else {
        None
    }
}

fn extract_posted_on(html: &str, href: &str) -> Option<String> {
    let pos = html.find(href)?;
    let end = (pos + href.len() + 200).min(html.len());
    let snippet = &html[pos..end];
    let re = Regex::new(r"(\d{4}-\d{2}-\d{2})").ok()?;
    re.captures(snippet)
        .and_then(|c| c.get(1))
        .map(|m| m.as_str().to_string())
}

pub fn parse_listings(html: &str, base_url: &str, source: JobBoardSource) -> Vec<ScrapedJobListing> {
    let re = match Regex::new(source.list_link_pattern()) {
        Ok(r) => r,
        Err(_) => return vec![],
    };
    let mut listings = Vec::new();
    let mut seen = HashSet::new();

    for cap in re.captures_iter(html) {
        let href = cap.get(1).map(|m| m.as_str()).unwrap_or("").trim();
        if href.is_empty() {
            continue;
        }
        let Some(url) = absolute_url(href, base_url) else {
            continue;
        };
        let path = path_from_url(&url);
        if !seen.insert(path.clone()) {
            continue;
        }
        let title = extract_link_title(html, href).unwrap_or_else(|| {
            path.split('/')
                .next_back()
                .unwrap_or("Role")
                .replace('-', " ")
        });
        let external_id = path
            .split('/')
            .next_back()
            .filter(|s| !s.is_empty())
            .unwrap_or(&path)
            .to_string();
        listings.push(ScrapedJobListing {
            external_id,
            external_path: path,
            title,
            location: extract_nearby_location(html, href).unwrap_or_default(),
            url,
            posted_at: extract_posted_on(html, href),
            source: source.id().to_string(),
        });
    }
    listings
}

pub async fn sync_source_listings(
    source: JobBoardSource,
    hub_url: Option<String>,
) -> Result<(JobBoardSyncSourceResult, Vec<ScrapedJobListing>)> {
    let base = hub_url
        .filter(|s| !s.trim().is_empty())
        .unwrap_or_else(|| source.default_hub_url().to_string());

    if !source.validate_hub_url(&base) {
        anyhow::bail!("Hub URL is not allowed for {}", source.label());
    }

    let mut page = 1usize;
    let mut all = Vec::new();
    let mut seen_paths = HashSet::new();

    while page <= MAX_LIST_PAGES && all.len() < MAX_LISTINGS {
        let page_url = source.listing_page_url(&base, page);
        let (preview, html) = fetch_html(&page_url)
            .await
            .with_context(|| format!("fetch {} page {page}", source.label()))?;

        if is_cloudflare_block(&html, preview.status) {
            anyhow::bail!("{} blocked the request (rate limit / bot check)", source.label());
        }

        let page_listings = parse_listings(&html, &page_url, source);
        if page_listings.is_empty() {
            break;
        }

        let mut added = 0usize;
        for listing in page_listings {
            if seen_paths.insert(listing.external_path.clone()) {
                all.push(listing);
                added += 1;
                if all.len() >= MAX_LISTINGS {
                    break;
                }
            }
        }
        if added == 0 {
            break;
        }
        page += 1;
    }

    Ok((
        JobBoardSyncSourceResult {
            source: source.id().to_string(),
            label: source.label().to_string(),
            imported: 0,
            updated: 0,
            skipped: 0,
            fetched: all.len() as i64,
            error: None,
        },
        all,
    ))
}

pub async fn sync_sources(sources: Vec<JobBoardSource>) -> Result<(JobBoardSyncResult, Vec<(JobBoardSource, Vec<ScrapedJobListing>)>)> {
    let mut per_source = Vec::new();
    let mut source_results = Vec::new();

    for source in sources {
        match sync_source_listings(source, None).await {
            Ok((mut result, listings)) => {
                result.fetched = listings.len() as i64;
                per_source.push((source, listings));
                source_results.push(result);
            }
            Err(e) => {
                source_results.push(JobBoardSyncSourceResult {
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

    let imported: i64 = source_results.iter().map(|s| s.imported).sum();
    let updated: i64 = source_results.iter().map(|s| s.updated).sum();
    let skipped: i64 = source_results.iter().map(|s| s.skipped).sum();
    let fetched: i64 = source_results.iter().map(|s| s.fetched).sum();

    Ok((
        JobBoardSyncResult {
            imported,
            updated,
            skipped,
            fetched,
            sources: source_results,
        },
        per_source,
    ))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_remoteok_fixture_links() {
        let html = r#"<a href="/remote-jobs/12345-senior-engineer-remote">Senior Engineer</a>"#;
        let listings = parse_listings(html, "https://remoteok.com/remote-jobs", JobBoardSource::RemoteOk);
        assert_eq!(listings.len(), 1);
        assert_eq!(listings[0].title, "Senior Engineer");
        assert!(listings[0].url.contains("/remote-jobs/12345"));
    }
}
