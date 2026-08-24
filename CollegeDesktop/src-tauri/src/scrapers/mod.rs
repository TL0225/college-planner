//! Universal scrapers (CourseLeaf / ModernCampus / HTML preview).
//! Embedded portal webviews are hosted by Tauri (WKWebView / WebView2).

mod company_board;
mod company_board_ats;
mod courseleaf;
mod job_board;
mod moderncampus;
mod politeness;
mod usajobs;

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};

pub use company_board::{detect_platform, scrape_company_board, CompanyBoardPlatform};
pub use courseleaf::{CourseLeafCourse, CourseLeafScraper};
pub use job_board::{
    all_sources, parse_listings, sync_source_listings, sync_sources, JobBoardSource,
    JobBoardSyncResult, JobBoardSyncSourceResult, ScrapedJobListing,
};
pub use moderncampus::ModernCampusScraper;
pub use politeness::FetchPoliteness;
pub use usajobs::sync_listings as sync_usajobs_listings;

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct HtmlPreview {
    pub url: String,
    pub title: String,
    pub text_excerpt: String,
    pub status: u16,
}

pub async fn fetch_html_preview(url: &str) -> Result<HtmlPreview> {
    let (preview, _) = fetch_html(url).await?;
    Ok(preview)
}

/// Fetch raw text (e.g. ICS calendar feeds).
pub async fn fetch_text(url: &str) -> Result<String> {
    FetchPoliteness::global().await_slot(url).await;

    let client = reqwest::Client::builder()
        .user_agent("CollegeDesktop/0.1 (+https://college.app)")
        .timeout(std::time::Duration::from_secs(20))
        .build()?;

    let response = client.get(url).send().await.context("HTTP GET failed")?;
    if !response.status().is_success() {
        anyhow::bail!("HTTP {} fetching {}", response.status(), url);
    }
    response.text().await.context("read body")
}

/// Fetch full HTML for ingest parsers (also returns a compact preview).
pub async fn fetch_html(url: &str) -> Result<(HtmlPreview, String)> {
    FetchPoliteness::global().await_slot(url).await;

    let client = reqwest::Client::builder()
        .user_agent("CollegeDesktop/0.1 (+https://college.app)")
        .timeout(std::time::Duration::from_secs(20))
        .build()?;

    let response = client.get(url).send().await.context("HTTP GET failed")?;
    let status = response.status().as_u16();
    let body = response.text().await.context("read body")?;

    let document = scraper::Html::parse_document(&body);
    let title_sel = scraper::Selector::parse("title").unwrap();
    let title = document
        .select(&title_sel)
        .next()
        .map(|n| n.text().collect::<String>())
        .unwrap_or_default()
        .trim()
        .to_string();

    let text: String = body
        .chars()
        .filter(|c| !c.is_control() || *c == '\n' || *c == '\t')
        .take(1200)
        .collect();

    Ok((
        HtmlPreview {
            url: url.to_string(),
            title,
            text_excerpt: text,
            status,
        },
        body,
    ))
}
