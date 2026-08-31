//! Windows Search indexer helpers and vault document registration.

use anyhow::{Context, Result};
use serde::Serialize;
use std::fs;
use std::path::Path;

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SearchIndexStatus {
    pub indexed_paths: usize,
    pub catalog_file: String,
}

/// Maintain a sidecar catalog JSON for Windows Search protocol handler consumption.
pub fn sync_vault_catalog(vault_root: &Path, entries: &[SearchIndexEntry]) -> Result<SearchIndexStatus> {
    fs::create_dir_all(vault_root)?;
    let catalog = vault_root.join("windows-search-catalog.json");
    fs::write(&catalog, serde_json::to_string_pretty(entries)?).context("write search catalog")?;
    Ok(SearchIndexStatus {
        indexed_paths: entries.len(),
        catalog_file: catalog.to_string_lossy().into_owned(),
    })
}

#[derive(Debug, Clone, Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SearchIndexEntry {
    pub id: String,
    pub title: String,
    pub path: String,
    pub category: Option<String>,
    pub updated_at: Option<String>,
}
