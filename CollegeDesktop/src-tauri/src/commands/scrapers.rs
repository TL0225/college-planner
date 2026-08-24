use crate::commands::CmdResult;
use crate::scrapers::{fetch_html_preview, HtmlPreview};

#[tauri::command]
pub async fn scraper_fetch_html_preview(url: String) -> CmdResult<HtmlPreview> {
    fetch_html_preview(&url).await.map_err(Into::into)
}
