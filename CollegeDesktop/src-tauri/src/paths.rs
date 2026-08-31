//! Cross-platform application data paths.
//!
//! Single portable database: `College.sqlite` holds all domains (including finance).
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
    /// Same path as `college_db` — finance lives in the shared College.sqlite.
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
            vault_dir: root.join("Vault"),
            models_dir: root.join("Models"),
            cache_dir: root.join("Cache"),
            backups_dir: root.join("Backups"),
            root,
        })
    }

    /// Legacy sidecar path — if present, finance rows are migrated into College.sqlite once.
    pub fn legacy_finance_sidecar(&self) -> PathBuf {
        self.root.join("Finance.sqlite")
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

    /// Absorb a leftover empty/unused Finance.sqlite sidecar (data already in College.sqlite).
    pub fn retire_legacy_finance_sidecar(&self) -> Result<()> {
        let sidecar = self.legacy_finance_sidecar();
        if !sidecar.exists() {
            return Ok(());
        }
        let retired = self.root.join("Finance.sqlite.retired");
        if !retired.exists() {
            let _ = fs::rename(&sidecar, &retired);
            tracing::info!(
                path = %retired.display(),
                "Retired unused Finance.sqlite sidecar; all finance data uses College.sqlite"
            );
        }
        Ok(())
    }

    pub fn to_dto(&self) -> StoragePathsDto {
        let db = self.college_db_path.display().to_string();
        StoragePathsDto {
            root: self.root.display().to_string(),
            college_db: db.clone(),
            finance_db: db,
            vault_dir: self.vault_dir.display().to_string(),
            models_dir: self.models_dir.display().to_string(),
            cache_dir: self.cache_dir.display().to_string(),
            backups_dir: self.backups_dir.display().to_string(),
        }
    }
}

/// Native Swift College.sqlite — Application Support root (not CollegeDesktop). macOS only.
#[cfg(target_os = "macos")]
pub fn swift_college_db_path() -> Option<PathBuf> {
    dirs::home_dir().map(|h| h.join("Library/Application Support/College.sqlite"))
}

#[cfg(not(target_os = "macos"))]
pub fn swift_college_db_path() -> Option<PathBuf> {
    None
}

#[cfg(target_os = "macos")]
pub fn swift_finance_db_path() -> Option<PathBuf> {
    dirs::home_dir().map(|h| {
        h.join("Library/Application Support/CollegeFinance/Finance.sqlite")
    })
}

#[cfg(not(target_os = "macos"))]
pub fn swift_finance_db_path() -> Option<PathBuf> {
    None
}

#[cfg(target_os = "macos")]
pub fn swift_document_vault_path() -> Option<PathBuf> {
    dirs::home_dir().map(|h| {
        h.join("Library/Application Support/College/DocumentVault")
    })
}

#[cfg(not(target_os = "macos"))]
pub fn swift_document_vault_path() -> Option<PathBuf> {
    None
}
