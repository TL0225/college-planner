//! Windows 11 Widgets Board feed export.
//!
//! Full `IWidgetProvider` COM registration requires a separate WinUI 3 package with
//! package identity. This module exports Adaptive Card JSON to disk so a future widget
//! provider (or third-party consumer) can read live College data.

use serde::Serialize;
use std::path::{Path, PathBuf};

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct WidgetFeed {
    pub id: String,
    pub title: String,
    pub template: String,
    pub data: serde_json::Value,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct WidgetsStatus {
    /// True only when a registered College widget provider package is detected.
    pub provider_registered: bool,
    pub feeds: Vec<WidgetFeed>,
    /// Absolute path to the exported feeds JSON (always written when feeds are built).
    pub feed_export_path: Option<String>,
}

fn widget_provider_installed() -> bool {
    if let Ok(local) = std::env::var("LOCALAPPDATA") {
        let packages = Path::new(&local)
            .join("Microsoft")
            .join("WindowsApps");
        if packages.is_dir() {
            if let Ok(entries) = std::fs::read_dir(packages) {
                for entry in entries.flatten() {
                    let name = entry.file_name().to_string_lossy().to_lowercase();
                    if name.contains("college") && name.contains("widget") {
                        return true;
                    }
                }
            }
        }
    }
    false
}

fn export_feeds(root: &Path, feeds: &[WidgetFeed]) -> Option<PathBuf> {
    let dir = root.join("Widgets");
    if std::fs::create_dir_all(&dir).is_err() {
        return None;
    }
    let path = dir.join("feeds.json");
    let payload = serde_json::json!({
        "version": 1,
        "updatedAt": chrono::Utc::now().to_rfc3339(),
        "feeds": feeds,
    });
    if serde_json::to_writer_pretty(
        std::fs::File::create(&path).ok()?,
        &payload,
    )
    .is_ok()
    {
        Some(path)
    } else {
        None
    }
}

/// Build adaptive card payloads and export to `{data}/Widgets/feeds.json`.
pub fn build_widget_feeds(
    data_root: &Path,
    agenda: Option<serde_json::Value>,
    gpa: Option<serde_json::Value>,
    pipeline: Option<serde_json::Value>,
) -> WidgetsStatus {
    let mut feeds = Vec::new();

    if let Some(data) = agenda {
        feeds.push(WidgetFeed {
            id: "college-daily-agenda".into(),
            title: "College Daily Agenda".into(),
            template: "AdaptiveCard.v1".into(),
            data,
        });
    }
    if let Some(data) = gpa {
        feeds.push(WidgetFeed {
            id: "college-academic-progress".into(),
            title: "Academic Progress".into(),
            template: "AdaptiveCard.v1".into(),
            data,
        });
    }
    if let Some(data) = pipeline {
        feeds.push(WidgetFeed {
            id: "college-career-pulse".into(),
            title: "Career Pulse".into(),
            template: "AdaptiveCard.v1".into(),
            data,
        });
    }

    let feed_export_path = export_feeds(data_root, &feeds).map(|p| p.display().to_string());

    WidgetsStatus {
        provider_registered: widget_provider_installed(),
        feeds,
        feed_export_path,
    }
}
