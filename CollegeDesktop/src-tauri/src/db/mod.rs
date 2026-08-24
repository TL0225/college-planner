//! SQLite storage engine with schema parity to CollegeGRDB.

mod schema;

use anyhow::{Context, Result};
use parking_lot::Mutex;
use r2d2::Pool;
use r2d2_sqlite::SqliteConnectionManager;
use rusqlite::{params, Connection, OptionalExtension};
use serde::{Deserialize, Serialize};
use std::path::Path;
use std::sync::Arc;

pub use schema::*;

pub type DbPool = Pool<SqliteConnectionManager>;

#[derive(Clone)]
pub struct AppDb {
    pool: Arc<DbPool>,
    path: std::path::PathBuf,
}

impl AppDb {
    pub fn open(path: &Path) -> Result<Self> {
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)?;
        }

        let manager = SqliteConnectionManager::file(path).with_init(|c| {
            c.execute_batch(
                "
                PRAGMA foreign_keys = ON;
                PRAGMA journal_mode = WAL;
                PRAGMA synchronous = NORMAL;
                PRAGMA temp_store = MEMORY;
                ",
            )?;
            Ok(())
        });

        let pool = Pool::builder()
            .max_size(8)
            .build(manager)
            .context("failed to create SQLite pool")?;

        Ok(Self {
            pool: Arc::new(pool),
            path: path.to_path_buf(),
        })
    }

    pub fn migrate(&self) -> Result<()> {
        let conn = self.pool.get().context("db pool")?;
        schema::run_migrations(&conn)?;
        Ok(())
    }

    pub fn with_conn<T, F>(&self, f: F) -> Result<T>
    where
        F: FnOnce(&Connection) -> Result<T>,
    {
        let conn = self.pool.get().context("db pool")?;
        f(&conn)
    }

    pub fn path(&self) -> &Path {
        &self.path
    }

    pub fn bump_revision(&self, domain: &str) -> Result<i64> {
        self.with_conn(|conn| {
            conn.execute(
                "INSERT INTO college_metadata (key, value, updated_at)
                 VALUES (?1, '1', datetime('now'))
                 ON CONFLICT(key) DO UPDATE SET
                   value = CAST(CAST(value AS INTEGER) + 1 AS TEXT),
                   updated_at = datetime('now')",
                params![format!("revision.{domain}")],
            )?;
            let rev: i64 = conn.query_row(
                "SELECT CAST(value AS INTEGER) FROM college_metadata WHERE key = ?1",
                params![format!("revision.{domain}")],
                |r| r.get(0),
            )?;
            Ok(rev)
        })
    }

    pub fn get_setting(&self, key: &str) -> Result<Option<String>> {
        self.with_conn(|conn| {
            let value = conn
                .query_row(
                    "SELECT value FROM app_settings WHERE key = ?1",
                    params![key],
                    |r| r.get::<_, String>(0),
                )
                .optional()?;
            Ok(value)
        })
    }

    pub fn set_setting(&self, key: &str, value: &str) -> Result<()> {
        self.with_conn(|conn| {
            conn.execute(
                "INSERT INTO app_settings (key, value, updated_at)
                 VALUES (?1, ?2, datetime('now'))
                 ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = datetime('now')",
                params![key, value],
            )?;
            Ok(())
        })
    }
}

/// Shared change notifier for Tauri events.
#[derive(Default)]
pub struct DbChangeBus {
    inner: Mutex<Vec<(String, i64)>>,
}

impl DbChangeBus {
    pub fn push(&self, domain: &str, revision: i64) {
        self.inner.lock().push((domain.to_string(), revision));
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DbChangeEvent {
    pub domain: String,
    pub revision: i64,
}
