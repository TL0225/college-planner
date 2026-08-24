//! Per-company career board scrapers (Greenhouse / Workday / Lever).
//! Mirrors Swift `GreenhouseScraper`, `WorkdayScraper` (list POST), and Lever postings API.

use crate::scrapers::{fetch_html, ScrapedJobListing};
use anyhow::{Context, Result};
use regex::Regex;
use serde::Deserialize;
use serde_json::Value;
use std::collections::hash_map::DefaultHasher;
use std::hash::{Hash, Hasher};

const MAX_WORKDAY_PAGES: usize = 8;
const WORKDAY_PAGE_SIZE: usize = 20;
const MAX_LISTINGS: usize = 160;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CompanyBoardPlatform {
    Greenhouse,
    Workday,
    Lever,
    Oracle,
    Icims,
    Talemetry,
}

impl CompanyBoardPlatform {
    pub fn id(self) -> &'static str {
        match self {
            Self::Greenhouse => "greenhouse",
            Self::Workday => "workday",
            Self::Lever => "lever",
            Self::Oracle => "oracle",
            Self::Icims => "icims",
            Self::Talemetry => "talemetry",
        }
    }

    pub fn label(self) -> &'static str {
        match self {
            Self::Greenhouse => "Greenhouse",
            Self::Workday => "Workday",
            Self::Lever => "Lever",
            Self::Oracle => "Oracle HCM",
            Self::Icims => "iCIMS",
            Self::Talemetry => "Talemetry",
        }
    }
}

pub fn detect_platform(url: &str) -> Option<CompanyBoardPlatform> {
    let lower = url.to_ascii_lowercase();
    if lower.contains("greenhouse.io") || lower.contains("boards.greenhouse.io") {
        Some(CompanyBoardPlatform::Greenhouse)
    } else if lower.contains("myworkdayjobs.com") || lower.contains("workdayjobs.com") {
        Some(CompanyBoardPlatform::Workday)
    } else if lower.contains("lever.co") || lower.contains("jobs.lever.co") {
        Some(CompanyBoardPlatform::Lever)
    } else if lower.contains("oraclecloud.com") || lower.contains("taleo.net") {
        Some(CompanyBoardPlatform::Oracle)
    } else if lower.contains("icims.com") || lower.contains("jobs.icims.com") {
        Some(CompanyBoardPlatform::Icims)
    } else if lower.contains("talemetry.com") || lower.contains("jobvite.com") {
        Some(CompanyBoardPlatform::Talemetry)
    } else {
        None
    }
}

pub async fn scrape_company_board(
    display_name: &str,
    careers_url: &str,
) -> Result<Vec<ScrapedJobListing>> {
    let platform = detect_platform(careers_url).ok_or_else(|| {
        anyhow::anyhow!(
            "Unsupported board URL — Greenhouse, Workday, Lever, Oracle, iCIMS, or Talemetry/Jobvite"
        )
    })?;
    match platform {
        CompanyBoardPlatform::Greenhouse => scrape_greenhouse(display_name, careers_url).await,
        CompanyBoardPlatform::Workday => scrape_workday(display_name, careers_url).await,
        CompanyBoardPlatform::Lever => scrape_lever(display_name, careers_url).await,
        CompanyBoardPlatform::Oracle => {
            crate::scrapers::company_board_ats::scrape_oracle(display_name, careers_url).await
        }
        CompanyBoardPlatform::Icims => {
            crate::scrapers::company_board_ats::scrape_icims(display_name, careers_url).await
        }
        CompanyBoardPlatform::Talemetry => {
            crate::scrapers::company_board_ats::scrape_talemetry(display_name, careers_url).await
        }
    }
}

fn strip_url_query_fragment(url: &str) -> String {
    let mut s = url.trim().to_string();
    if let Some(i) = s.find('#') {
        s.truncate(i);
    }
    if let Some(i) = s.find('?') {
        s.truncate(i);
    }
    s
}

fn url_host_path(url: &str) -> Option<(String, Vec<String>)> {
    let trimmed = strip_url_query_fragment(url);
    let without_scheme = trimmed
        .strip_prefix("https://")
        .or_else(|| trimmed.strip_prefix("http://"))?;
    let (host, path) = without_scheme
        .split_once('/')
        .map(|(h, p)| (h.to_string(), p.to_string()))
        .unwrap_or_else(|| (without_scheme.to_string(), String::new()));
    let segments: Vec<String> = path
        .split('/')
        .filter(|s| !s.is_empty())
        .map(|s| s.to_string())
        .collect();
    Some((host.to_ascii_lowercase(), segments))
}

fn query_param(url: &str, key: &str) -> Option<String> {
    let q = url.split_once('?')?.1.split('#').next()?;
    for pair in q.split('&') {
        let mut parts = pair.splitn(2, '=');
        let k = parts.next()?;
        let v = parts.next().unwrap_or("");
        if k == key && !v.is_empty() {
            return Some(urlencoding::decode(v).unwrap_or_else(|_| v.into()).into_owned());
        }
    }
    None
}

fn greenhouse_board_token(url: &str) -> Option<String> {
    if let Some(for_token) = query_param(url, "for") {
        if !for_token.trim().is_empty() {
            return Some(for_token);
        }
    }
    let (host, segments) = url_host_path(url)?;
    if host.contains("boards.greenhouse.io") {
        return segments.first().cloned().filter(|s| !s.is_empty());
    }
    None
}

#[derive(Debug, Deserialize)]
struct GreenhouseJobsResponse {
    jobs: Vec<GreenhouseJob>,
}

#[derive(Debug, Deserialize)]
struct GreenhouseJob {
    id: i64,
    title: String,
    location: Option<GreenhouseLocation>,
    #[serde(default, rename = "updated_at")]
    updated_at: Option<String>,
    #[serde(default, rename = "absolute_url")]
    absolute_url: Option<String>,
}

#[derive(Debug, Deserialize)]
struct GreenhouseLocation {
    name: Option<String>,
}

async fn scrape_greenhouse(display_name: &str, careers_url: &str) -> Result<Vec<ScrapedJobListing>> {
    let token = greenhouse_board_token(careers_url)
        .ok_or_else(|| anyhow::anyhow!("Could not parse Greenhouse board token from URL"))?;
    let api = format!("https://boards-api.greenhouse.io/v1/boards/{token}/jobs?content=true");
    let client = reqwest::Client::builder()
        .user_agent("CollegeDesktop/0.1 (+https://college.app)")
        .timeout(std::time::Duration::from_secs(30))
        .build()?;
    let resp = client.get(&api).send().await.context("Greenhouse API GET")?;
    if !resp.status().is_success() {
        anyhow::bail!("Greenhouse API HTTP {}", resp.status());
    }
    let body: GreenhouseJobsResponse = resp.json().await.context("Greenhouse JSON")?;
    let company = if display_name.trim().is_empty() {
        token.clone()
    } else {
        display_name.trim().to_string()
    };
    let mut out = Vec::new();
    for job in body.jobs.into_iter().take(MAX_LISTINGS) {
        let url = job
            .absolute_url
            .unwrap_or_else(|| format!("https://boards.greenhouse.io/{token}/jobs/{}", job.id));
        out.push(ScrapedJobListing {
            external_id: job.id.to_string(),
            external_path: job.id.to_string(),
            title: job.title,
            location: job.location.and_then(|l| l.name).unwrap_or_default(),
            url,
            posted_at: job.updated_at,
            source: format!("greenhouse:{company}"),
        });
    }
    Ok(out)
}

fn lever_company_slug(url: &str) -> Option<String> {
    let (host, segments) = url_host_path(url)?;
    if host.contains("jobs.lever.co") || host.contains("lever.co") {
        return segments.first().cloned().filter(|s| !s.is_empty());
    }
    None
}

#[derive(Debug, Deserialize)]
struct LeverPosting {
    id: Option<String>,
    text: Option<String>,
    #[serde(default, rename = "hostedUrl")]
    hosted_url: Option<String>,
    #[serde(default)]
    categories: Option<LeverCategories>,
    #[serde(default, rename = "createdAt")]
    created_at: Option<i64>,
}

#[derive(Debug, Deserialize)]
struct LeverCategories {
    location: Option<String>,
}

fn hash_id(title: &str) -> String {
    let mut h = DefaultHasher::new();
    title.hash(&mut h);
    format!("{:x}", h.finish())
}

async fn scrape_lever(display_name: &str, careers_url: &str) -> Result<Vec<ScrapedJobListing>> {
    let slug = lever_company_slug(careers_url)
        .ok_or_else(|| anyhow::anyhow!("Could not parse Lever company slug from URL"))?;
    let api = format!("https://api.lever.co/v0/postings/{slug}?mode=json");
    let client = reqwest::Client::builder()
        .user_agent("CollegeDesktop/0.1 (+https://college.app)")
        .timeout(std::time::Duration::from_secs(30))
        .build()?;
    let resp = client.get(&api).send().await.context("Lever API GET")?;
    if !resp.status().is_success() {
        anyhow::bail!("Lever API HTTP {}", resp.status());
    }
    let jobs: Vec<LeverPosting> = resp.json().await.context("Lever JSON")?;
    let company = if display_name.trim().is_empty() {
        slug.clone()
    } else {
        display_name.trim().to_string()
    };
    let mut out = Vec::new();
    for job in jobs.into_iter().take(MAX_LISTINGS) {
        let id = job
            .id
            .clone()
            .unwrap_or_else(|| hash_id(job.text.as_deref().unwrap_or("")));
        let url = job
            .hosted_url
            .unwrap_or_else(|| format!("https://jobs.lever.co/{slug}/{id}"));
        let posted_at = job.created_at.and_then(|ms| {
            chrono::DateTime::from_timestamp_millis(ms).map(|dt| dt.to_rfc3339())
        });
        out.push(ScrapedJobListing {
            external_id: id,
            external_path: job.id.unwrap_or_default(),
            title: job.text.unwrap_or_default(),
            location: job.categories.and_then(|c| c.location).unwrap_or_default(),
            url,
            posted_at,
            source: format!("lever:{company}"),
        });
    }
    Ok(out)
}

fn is_locale_segment(segment: &str) -> bool {
    let lower = segment.to_ascii_lowercase();
    if lower == "job" || lower == "jobs" {
        return false;
    }
    Regex::new(r"^[a-z]{2}(-[A-Za-z]{2,4})?(-x-[a-z]+)?$")
        .ok()
        .map(|r| r.is_match(segment))
        .unwrap_or(false)
}

fn normalize_workday_careers_url(url: &str) -> String {
    let trimmed = strip_url_query_fragment(url);
    let Some((host, mut segs)) = url_host_path(&trimmed) else {
        return trimmed;
    };
    if let Some(job_idx) = segs
        .iter()
        .position(|s| s.eq_ignore_ascii_case("job"))
        .filter(|&i| i > 0)
    {
        segs.truncate(job_idx);
    }
    if segs
        .last()
        .map(|s| s.eq_ignore_ascii_case("jobs"))
        .unwrap_or(false)
    {
        segs.pop();
    }
    if segs.is_empty() {
        format!("https://{host}")
    } else {
        format!("https://{host}/{}", segs.join("/"))
    }
}

fn derive_workday_context(careers_url: &str) -> Option<(String, String, String, String)> {
    let normalized = normalize_workday_careers_url(careers_url);
    let (host, path) = url_host_path(&normalized)?;
    if !host.contains("myworkdayjobs.com") {
        return None;
    }
    let tenant = host.split('.').next()?.to_string();
    if tenant.is_empty() || path.is_empty() {
        return None;
    }
    let mut board_index = 0usize;
    if path.first().map(|s| is_locale_segment(s)).unwrap_or(false) {
        board_index = 1;
    }
    let board = path.get(board_index)?.clone();
    Some((tenant, board, host, normalized))
}

fn parse_embedded_site_config(html: &str) -> Option<(String, String)> {
    let tenant_re = Regex::new(r#"tenant:\s*"([^"]+)""#).ok()?;
    let site_re = Regex::new(r#"siteId:\s*"([^"]+)""#).ok()?;
    let tenant = tenant_re.captures(html)?.get(1)?.as_str().to_string();
    let site_id = site_re.captures(html)?.get(1)?.as_str().to_string();
    if tenant.is_empty() || site_id.is_empty() {
        return None;
    }
    Some((tenant, site_id))
}

async fn scrape_workday(display_name: &str, careers_url: &str) -> Result<Vec<ScrapedJobListing>> {
    let (mut tenant, mut board, host, careers) = derive_workday_context(careers_url)
        .ok_or_else(|| anyhow::anyhow!("Could not parse Workday board URL"))?;

    if let Ok((_, html)) = fetch_html(&careers).await {
        if html
            .to_ascii_lowercase()
            .contains("community.workday.com/maintenance-page")
        {
            anyhow::bail!("Workday careers site is temporarily down for maintenance");
        }
        if let Some((t, s)) = parse_embedded_site_config(&html) {
            tenant = t;
            board = s;
        }
    }

    let list_url = format!("https://{host}/wday/cxs/{tenant}/{board}/jobs");
    let client = reqwest::Client::builder()
        .user_agent(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 CollegeDesktop/0.1",
        )
        .timeout(std::time::Duration::from_secs(30))
        .build()?;

    let _ = client
        .get(&careers)
        .header("Accept", "text/html")
        .send()
        .await;

    let company = if display_name.trim().is_empty() {
        tenant.clone()
    } else {
        display_name.trim().to_string()
    };

    let mut out = Vec::new();
    let mut offset = 0usize;
    for _ in 0..MAX_WORKDAY_PAGES {
        let body = serde_json::json!({
            "appliedFacets": {},
            "limit": WORKDAY_PAGE_SIZE,
            "offset": offset,
            "searchText": ""
        });
        let resp = client
            .post(&list_url)
            .header("Content-Type", "application/json")
            .header("Accept", "application/json")
            .header("Referer", &careers)
            .json(&body)
            .send()
            .await
            .context("Workday jobs POST")?;
        if !resp.status().is_success() {
            anyhow::bail!("Workday API HTTP {} for {list_url}", resp.status());
        }
        let json: Value = resp.json().await.context("Workday JSON")?;
        if let Some(code) = json.get("errorCode").and_then(|v| v.as_str()) {
            if json.get("jobPostings").is_none() {
                let msg = json
                    .get("message")
                    .and_then(|v| v.as_str())
                    .unwrap_or(code);
                anyhow::bail!("Workday API error: {msg}");
            }
        }
        let postings = json
            .get("jobPostings")
            .and_then(|v| v.as_array())
            .cloned()
            .unwrap_or_default();
        let received = postings.len();
        for job in postings {
            if out.len() >= MAX_LISTINGS {
                break;
            }
            let title = job
                .get("title")
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .to_string();
            let external_path = job
                .get("externalPath")
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .to_string();
            if title.is_empty() && external_path.is_empty() {
                continue;
            }
            let location = job
                .get("locationsText")
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .to_string();
            let posted_at = job
                .get("postedOn")
                .and_then(|v| v.as_str())
                .map(|s| s.to_string());
            let path = if external_path.starts_with('/') {
                external_path.clone()
            } else {
                format!("/{external_path}")
            };
            let url = format!("{}{}", careers.trim_end_matches('/'), path);
            let external_id = external_path
                .rsplit('_')
                .next()
                .filter(|s| s.starts_with('R'))
                .unwrap_or(external_path.as_str())
                .to_string();
            out.push(ScrapedJobListing {
                external_id,
                external_path,
                title,
                location,
                url,
                posted_at,
                source: format!("workday:{company}"),
            });
        }
        if received < WORKDAY_PAGE_SIZE || out.len() >= MAX_LISTINGS {
            break;
        }
        offset += WORKDAY_PAGE_SIZE;
    }

    Ok(out)
}
