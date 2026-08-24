use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CourseLeafCourse {
    pub code: String,
    pub title: String,
    pub credits: Option<f64>,
    pub description: String,
}

pub struct CourseLeafScraper;

impl CourseLeafScraper {
    /// Extract course-like rows from CourseLeaf HTML (heuristic).
    pub fn parse_courses(html: &str) -> Vec<CourseLeafCourse> {
        let document = scraper::Html::parse_document(html);
        let sel = scraper::Selector::parse(".courseblock, .course-listing, .detail").unwrap();
        let mut out = Vec::new();
        for el in document.select(&sel) {
            let text = el.text().collect::<Vec<_>>().join(" ");
            let code = extract_code(&text).unwrap_or_default();
            if code.is_empty() {
                continue;
            }
            out.push(CourseLeafCourse {
                code,
                title: text.chars().take(120).collect(),
                credits: None,
                description: text.chars().take(400).collect(),
            });
        }
        out
    }
}

fn extract_code(text: &str) -> Option<String> {
    let bytes = text.as_bytes();
    let mut i = 0;
    while i + 5 < bytes.len() {
        if bytes[i].is_ascii_uppercase() {
            let mut j = i;
            while j < bytes.len() && bytes[j].is_ascii_uppercase() && j - i < 4 {
                j += 1;
            }
            if j - i >= 2 {
                let mut k = j;
                while k < bytes.len() && (bytes[k] == b' ' || bytes[k] == b'-') {
                    k += 1;
                }
                let digit_start = k;
                while k < bytes.len() && bytes[k].is_ascii_digit() && k - digit_start < 3 {
                    k += 1;
                }
                if k - digit_start == 3 {
                    let dept = std::str::from_utf8(&bytes[i..j]).ok()?;
                    let num = std::str::from_utf8(&bytes[digit_start..k]).ok()?;
                    return Some(format!("{dept} {num}"));
                }
            }
        }
        i += 1;
    }
    None
}
