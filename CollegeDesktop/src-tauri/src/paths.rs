//! Cross-platform application data paths.
//!
//! macOS Tauri: ~/Library/Application Support/CollegeDesktop/
//!   (Swift native app keeps ~/Library/Application Support/College.sqlite)
//! Windows: %LocalAppData%\CollegeDesktop\

use anyhow::{Context, Result};
use serde::Serialize;
use std::fs;
use std::path::PathBuf;

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct StoragePathsDto {
    pub root: String,
    pub college_db: String,
    pub finance_db: String,
    pub vault_dir: String,
    pub models_dir: String,
    pub cache_dir: String,
    pub backups_dir: String,
}

#[derive(Debug, Clone)]
pub struct AppPaths {
    pub root: PathBuf,
    pub college_db_path: PathBuf,
    pub finance_db_path: PathBuf,
    pub vault_dir: PathBuf,
    pub models_dir: PathBuf,
    pub cache_dir: PathBuf,
    pub backups_dir: PathBuf,
}

impl AppPaths {
    pub fn resolve() -> Result<Self> {
        let root = dirs::data_local_dir()
            .context("could not resolve local data directory")?
            .join("CollegeDesktop");

        Ok(Self {
            college_db_path: root.join("College.sqlite"),
            finance_db_path: root.join("Finance.sqlite"),
            vault_dir: root.join("Vault"),
            models_dir: root.join("Models"),
            cache_dir: root.join("Cache"),
            backups_dir: root.join("Backups"),
            root,
        })
    }

    pub fn ensure_dirs(&self) -> Result<()> {
        for dir in [
            &self.root,
            &self.vault_dir,
            &self.models_dir,
            &self.cache_dir,
            &self.backups_dir,
        ] {
            fs::create_dir_all(dir)
                .with_context(|| format!("failed to create directory {}", dir.display()))?;
        }
        Ok(())
    }

    pub fn to_dto(&self) -> StoragePathsDto {
        StoragePathsDto {
            root: self.root.display().to_string(),
            college_db: self.college_db_path.display().to_string(),
            finance_db: self.finance_db_path.display().to_string(),
            vault_dir: self.vault_dir.display().to_string(),
            models_dir: self.models_dir.display().to_string(),
            cache_dir: self.cache_dir.display().to_string(),
            backups_dir: self.backups_dir.display().to_string(),
        }
    }
}

/// Native Swift College.sqlite — Application Support root (not CollegeDesktop).
pub fn swift_college_db_path() -> Option<PathBuf> {
    dirs::home_dir().map(|h| h.join("Library/Application Support/College.sqlite"))
}

pub fn swift_finance_db_path() -> Option<PathBuf> {
    dirs::home_dir().map(|h| {
        h.join("Library/Application Support/CollegeFinance/Finance.sqlite")
    })
}

pub fn swift_document_vault_path() -> Option<PathBuf> {
    dirs::home_dir().map(|h| {
        h.join("Library/Application Support/College/DocumentVault")
    })
}
