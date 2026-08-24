//! Oracle HCM, iCIMS/Jibe, and Talemetry/Jobvite company-board scrapers (Swift parity).

use crate::scrapers::{fetch_html, ScrapedJobListing};
use anyhow::{Context, Result};
use regex::Regex;
use serde_json::Value;

const MAX_LISTINGS: usize = 160;

pub async fn scrape_oracle(display_name: &str, careers_url: &str) -> Result<Vec<ScrapedJobListing>> {
    let (host, site) = resolve_oracle_context(careers_url).await?;
    let base = format!("https://{host}/");
    let company = display_name_or(display_name, &host);
    let apply_base = oracle_apply_base(careers_url, &host, &site);
    let client = http_client()?;
    let mut out = Vec::new();
    let mut offset = 0usize;
    let limit = 100usize;
    loop {
        if out.len() >= MAX_LISTINGS {
            break;
        }
        let finder = format!("findReqs;siteNumber={site},limit={limit},offset={offset}");
        let url = format!(
            "{base}hcmRestApi/resources/latest/recruitingCEJobRequisitions?finder={}&expand=requisitionList&onlyData=true",
            urlencoding::encode(&finder)
        );
        let resp = client
            .get(&url)
            .header("ora-irc-cx-userid", "00000000-0000-0000-0000-000000000000")
            .header("ora-irc-language", "en")
            .header(
                "Content-Type",
                "application/vnd.oracle.adf.resourceitem+json;charset=utf-8",
            )
            .send()
            .await
            .context("Oracle HCM GET")?;
        if !resp.status().is_success() {
            anyhow::bail!("Oracle HCM HTTP {}", resp.status());
        }
        let json: Value = resp.json().await.context("Oracle JSON")?;
        let items = json
            .get("items")
            .and_then(|v| v.as_array())
            .cloned()
            .unwrap_or_default();
        let Some(page) = items.first() else { break };
        let reqs = page
            .get("requisitionList")
            .and_then(|v| v.as_array())
            .cloned()
            .unwrap_or_default();
        if reqs.is_empty() {
            break;
        }
        let received = reqs.len();
        for item in reqs {
            if out.len() >= MAX_LISTINGS {
                break;
            }
            let id = item
                .get("Id")
                .or_else(|| item.get("id"))
                .and_then(|v| v.as_str().map(|s| s.to_string()).or_else(|| v.as_i64().map(|n| n.to_string())))
                .unwrap_or_default();
            if id.is_empty() {
                continue;
            }
            let title = item
                .get("Title")
                .or_else(|| item.get("title"))
                .and_then(|v| v.as_str())
                .unwrap_or("Untitled")
                .to_string();
            let location = item
                .get("PrimaryLocation")
                .or_else(|| item.get("primaryLocation"))
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .to_string();
            let posted = item
                .get("PostedDate")
                .or_else(|| item.get("postedDate"))
                .and_then(|v| v.as_str())
                .map(|s| s.to_string());
            let url = format!("{apply_base}/job/{id}");
            out.push(ScrapedJobListing {
                external_id: id.clone(),
                external_path: id,
                title,
                location,
                url,
                posted_at: posted,
                source: format!("oracle:{company}"),
            });
        }
        offset += received;
        let total = page
            .get("TotalJobsCount")
            .or_else(|| page.get("totalJobsCount"))
            .and_then(|v| v.as_i64())
            .unwrap_or(0) as usize;
        if total > 0 && offset >= total {
            break;
        }
        if received < limit {
            break;
        }
    }
    Ok(out)
}

async fn resolve_oracle_context(careers_url: &str) -> Result<(String, String)> {
    let host = host_of(careers_url).ok_or_else(|| anyhow::anyhow!("Invalid Oracle URL"))?;
    if !host.contains("oraclecloud.com") {
        anyhow::bail!("Oracle board URL must be on oraclecloud.com");
    }
    if let Some(site) = extract_oracle_site(careers_url) {
        return Ok((host, site));
    }
    let (_, html) = fetch_html(careers_url).await?;
    let site = extract_oracle_site(&html)
        .ok_or_else(|| anyhow::anyhow!("Could not find Oracle siteNumber (CX_…)"))?;
    Ok((host, site))
}

fn extract_oracle_site(text: &str) -> Option<String> {
    let patterns = [
        r#"/sites/(CX_\d+)"#,
        r#"siteNumber\s*[:=]\s*['"]?(CX_\d+)['"]?"#,
    ];
    for pat in patterns {
        if let Ok(re) = Regex::new(pat) {
            if let Some(c) = re.captures(text) {
                return c.get(1).map(|m| m.as_str().to_string());
            }
        }
    }
    None
}

fn oracle_apply_base(careers_url: &str, host: &str, site: &str) -> String {
    let path = path_of(careers_url).unwrap_or_default();
    if path.contains(&format!("/sites/{site}")) {
        let mut trimmed = path;
        if let Some(idx) = trimmed.find("/job/") {
            trimmed.truncate(idx);
        } else if trimmed.ends_with("/jobs") {
            trimmed.truncate(trimmed.len().saturating_sub(5));
        }
        return format!("https://{host}{trimmed}");
    }
    format!("https://{host}/hcmUI/CandidateExperience/en/sites/{site}")
}

pub async fn scrape_icims(display_name: &str, careers_url: &str) -> Result<Vec<ScrapedJobListing>> {
    let host = host_of(careers_url).ok_or_else(|| anyhow::anyhow!("Invalid iCIMS URL"))?;
    let base = format!("https://{host}");
    let company = display_name_or(display_name, &host);
    let client = http_client()?;

    if let Ok(list) = scrape_icims_jibe(&client, &base, &company).await {
        if !list.is_empty() {
            return Ok(list);
        }
    }

    // Fallback: sitemap.xml job URLs
    let sitemap = format!("{base}/sitemap.xml");
    let resp = client.get(&sitemap).send().await.context("iCIMS sitemap")?;
    if resp.status().is_success() {
        let xml = resp.text().await.unwrap_or_default();
        let re = Regex::new(r"<loc>(.*?)</loc>").unwrap();
        let mut out = Vec::new();
        for cap in re.captures_iter(&xml) {
            if out.len() >= MAX_LISTINGS {
                break;
            }
            let loc = cap.get(1).map(|m| m.as_str().trim()).unwrap_or("");
            if !loc.contains("/jobs/") || loc.contains("/jobs/search") {
                continue;
            }
            let id = loc
                .split('/')
                .skip_while(|s| *s != "jobs")
                .nth(1)
                .unwrap_or("")
                .to_string();
            if id.is_empty() {
                continue;
            }
            let title = id.replace('-', " ");
            out.push(ScrapedJobListing {
                external_id: id.clone(),
                external_path: id,
                title,
                location: String::new(),
                url: loc.to_string(),
                posted_at: None,
                source: format!("icims:{company}"),
            });
        }
        if !out.is_empty() {
            return Ok(out);
        }
    }

    anyhow::bail!("No iCIMS/Jibe listings found — check the careers URL")
}

async fn scrape_icims_jibe(
    client: &reqwest::Client,
    base: &str,
    company: &str,
) -> Result<Vec<ScrapedJobListing>> {
    let mut out = Vec::new();
    let mut page = 1usize;
    loop {
        if out.len() >= MAX_LISTINGS {
            break;
        }
        let url = format!("{base}/api/jobs?page={page}&limit=100");
        let resp = client.get(&url).send().await.context("Jibe API GET")?;
        if !resp.status().is_success() {
            anyhow::bail!("Jibe API HTTP {}", resp.status());
        }
        let json: Value = resp.json().await.context("Jibe JSON")?;
        let jobs = json
            .get("jobs")
            .and_then(|v| v.as_array())
            .cloned()
            .unwrap_or_default();
        if jobs.is_empty() {
            break;
        }
        let received = jobs.len();
        for entry in jobs {
            if out.len() >= MAX_LISTINGS {
                break;
            }
            let data = entry.get("data").cloned().unwrap_or(entry);
            let slug = data
                .get("slug")
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .to_string();
            if slug.is_empty() {
                continue;
            }
            let title = data
                .get("title")
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .to_string();
            let location = data
                .get("location_name")
                .or_else(|| data.get("locationName"))
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .to_string();
            let posted = data
                .get("posted_date")
                .or_else(|| data.get("postedDate"))
                .and_then(|v| v.as_str())
                .map(|s| s.to_string());
            let url = format!("{base}/jobs/{slug}");
            out.push(ScrapedJobListing {
                external_id: slug.clone(),
                external_path: slug,
                title,
                location,
                url,
                posted_at: posted,
                source: format!("icims:{company}"),
            });
        }
        let total = json.get("totalCount").and_then(|v| v.as_i64()).unwrap_or(0) as usize;
        if total > 0 && out.len() >= total {
            break;
        }
        if received < 100 {
            break;
        }
        page += 1;
        if page > 20 {
            break;
        }
    }
    Ok(out)
}

pub async fn scrape_talemetry(
    display_name: &str,
    careers_url: &str,
) -> Result<Vec<ScrapedJobListing>> {
    let host = host_of(careers_url).ok_or_else(|| anyhow::anyhow!("Invalid Talemetry URL"))?;
    let base = format!("https://{host}");
    let company = display_name_or(display_name, &host);
    let lower = careers_url.to_ascii_lowercase();
    if lower.contains("jobvite.com") {
        return scrape_jobvite_hosted(&base, careers_url, &company).await;
    }
    scrape_talemetry_search(&base, &company).await
}

async fn scrape_jobvite_hosted(
    base: &str,
    careers_url: &str,
    company: &str,
) -> Result<Vec<ScrapedJobListing>> {
    let (_, html) = fetch_html(careers_url).await?;
    let re = Regex::new(r#"href="([^"]*/job/[^"]+)""#).unwrap();
    let mut seen = std::collections::HashSet::new();
    let mut out = Vec::new();
    for cap in re.captures_iter(&html) {
        if out.len() >= MAX_LISTINGS {
            break;
        }
        let mut href = cap.get(1).map(|m| m.as_str()).unwrap_or("").to_string();
        if href.starts_with('/') {
            href = format!("{}{}", base.trim_end_matches('/'), href);
        }
        let id = href.rsplit('/').next().unwrap_or("").to_string();
        if id.is_empty() || !seen.insert(id.clone()) {
            continue;
        }
        let title = format!("Job {id}");
        out.push(ScrapedJobListing {
            external_id: id.clone(),
            external_path: id,
            title,
            location: String::new(),
            url: href,
            posted_at: None,
            source: format!("talemetry:{company}"),
        });
    }
    if out.is_empty() {
        anyhow::bail!("No Jobvite listings found on page");
    }
    Ok(out)
}

async fn scrape_talemetry_search(base: &str, company: &str) -> Result<Vec<ScrapedJobListing>> {
    let client = http_client()?;
    let mut out = Vec::new();
    let mut seen = std::collections::HashSet::new();
    let re = Regex::new(r#"href="(https://apply\.talemetry\.com[^"]+|[^"]*/jobs/[^"]+)""#).unwrap();
    for page in 1..=10usize {
        if out.len() >= MAX_LISTINGS {
            break;
        }
        let url = if page == 1 {
            format!("{base}/search/jobs")
        } else {
            format!("{base}/search/jobs?page={page}")
        };
        let resp = client.get(&url).send().await.context("Talemetry search")?;
        if !resp.status().is_success() {
            break;
        }
        let html = resp.text().await.unwrap_or_default();
        let before = out.len();
        for cap in re.captures_iter(&html) {
            if out.len() >= MAX_LISTINGS {
                break;
            }
            let mut href = cap.get(1).map(|m| m.as_str()).unwrap_or("").to_string();
            if href.starts_with('/') {
                href = format!("{}{}", base.trim_end_matches('/'), href);
            }
            let id = href.rsplit('/').next().unwrap_or("").to_string();
            if id.is_empty() || !seen.insert(id.clone()) {
                continue;
            }
            out.push(ScrapedJobListing {
                external_id: id.clone(),
                external_path: id.clone(),
                title: id.replace('-', " "),
                location: String::new(),
                url: href,
                posted_at: None,
                source: format!("talemetry:{company}"),
            });
        }
        if out.len() == before {
            break;
        }
    }
    if out.is_empty() {
        anyhow::bail!("No Talemetry listings found");
    }
    Ok(out)
}

fn http_client() -> Result<reqwest::Client> {
    Ok(reqwest::Client::builder()
        .user_agent("CollegeDesktop/0.1 (+https://college.app)")
        .timeout(std::time::Duration::from_secs(30))
        .build()?)
}

fn display_name_or(name: &str, fallback: &str) -> String {
    if name.trim().is_empty() {
        fallback.to_string()
    } else {
        name.trim().to_string()
    }
}

fn host_of(url: &str) -> Option<String> {
    let trimmed = url.trim();
    let without = trimmed
        .strip_prefix("https://")
        .or_else(|| trimmed.strip_prefix("http://"))?;
    Some(
        without
            .split('/')
            .next()?
            .split('?')
            .next()?
            .to_ascii_lowercase(),
    )
}

fn path_of(url: &str) -> Option<String> {
    let trimmed = url.trim();
    let without = trimmed
        .strip_prefix("https://")
        .or_else(|| trimmed.strip_prefix("http://"))?;
    let path = without.split_once('/').map(|(_, p)| p).unwrap_or("");
    let path = path.split('?').next().unwrap_or(path);
    if path.is_empty() {
        Some(String::new())
    } else {
        Some(format!("/{path}"))
    }
}
