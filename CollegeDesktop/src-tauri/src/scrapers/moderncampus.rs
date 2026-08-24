use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ModernCampusProgram {
    pub name: String,
    pub degree_type: String,
    pub url: String,
}

pub struct ModernCampusScraper;

impl ModernCampusScraper {
    pub fn parse_programs(html: &str, base_url: &str) -> Vec<ModernCampusProgram> {
        let document = scraper::Html::parse_document(html);
        let sel = scraper::Selector::parse("a").unwrap();
        let mut out = Vec::new();
        for el in document.select(&sel) {
            let href = el.value().attr("href").unwrap_or("");
            let name = el.text().collect::<String>().trim().to_string();
            if name.is_empty() || href.is_empty() {
                continue;
            }
            let lower = href.to_lowercase();
            if !(lower.contains("program") || lower.contains("degree") || lower.contains("major")) {
                continue;
            }
            let url = if href.starts_with("http") {
                href.to_string()
            } else {
                format!("{}/{}", base_url.trim_end_matches('/'), href.trim_start_matches('/'))
            };
            out.push(ModernCampusProgram {
                name,
                degree_type: String::new(),
                url,
            });
        }
        out
    }
}
