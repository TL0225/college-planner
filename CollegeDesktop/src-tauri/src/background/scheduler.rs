//! Tokio interval schedulers — finance recurring, discovery federal sync, calendar course linker.

use crate::commands::finance_connections::{self, COINBASE_API_KEY_SETTING};
use crate::db::DbChangeEvent;
use crate::AppState;
use chrono::{Duration, Utc};
use regex::Regex;
use std::sync::OnceLock;
use tauri::{AppHandle, Emitter, Manager};
use uuid::Uuid;

const FINANCE_INTERVAL: std::time::Duration = std::time::Duration::from_secs(6 * 3600);
const DISCOVERY_INTERVAL: std::time::Duration = std::time::Duration::from_secs(30 * 24 * 3600);
const CALENDAR_LINKER_INTERVAL: std::time::Duration = std::time::Duration::from_secs(24 * 3600);
const COINBASE_SYNC_INTERVAL: std::time::Duration = std::time::Duration::from_secs(24 * 3600);

fn course_code_regex() -> &'static Regex {
    static RE: OnceLock<Regex> = OnceLock::new();
    RE.get_or_init(|| {
        Regex::new(r"\b([A-Za-z]{2,4})\s*(\d{3,4})[A-Za-z]*\b").expect("course code regex")
    })
}

const EXCLUSION_PREFIXES: &[&str] = &[
    "AM", "PM", "AD", "BC", "ID", "IT", "AT", "BY", "OR", "IN", "TO", "GO", "NO", "OK", "US", "TV",
    "HD", "USB", "URL", "PDF", "GPA", "GPT", "AI", "API", "UI", "UX", "EST", "PST", "CST", "MST",
];

fn extract_course_code(title: &str) -> Option<String> {
    for caps in course_code_regex().captures_iter(title) {
        let prefix = caps.get(1)?.as_str().to_ascii_uppercase();
        let digits = caps.get(2)?.as_str();
        if EXCLUSION_PREFIXES.contains(&prefix.as_str()) {
            continue;
        }
        return Some(format!("{prefix}{digits}"));
    }
    None
}

fn advance_next_due(cadence: &str, current: &str) -> Option<String> {
    use chrono::NaiveDate;
    let date = NaiveDate::parse_from_str(&current[..10.min(current.len())], "%Y-%m-%d").ok()?;
    let next = match cadence.to_ascii_lowercase().as_str() {
        "weekly" => date + Duration::weeks(1),
        "yearly" | "annual" => date + Duration::days(365),
        _ => date + Duration::days(30),
    };
    Some(next.format("%Y-%m-%d").to_string())
}

fn post_due_recurring(app: &AppHandle, state: &AppState) {
    let now = Utc::now().to_rfc3339();
    let rows: Vec<(String, Option<String>, String, f64, String, String, String)> = match state
        .db
        .with_conn(|conn| {
            let mut stmt = conn.prepare(
                "SELECT id, account_id, title, amount, cadence, next_due, category
                 FROM finance_recurring
                 WHERE next_due IS NOT NULL AND next_due <= ?1",
            )?;
            let mapped = stmt.query_map(rusqlite::params![now], |r| {
                Ok((
                    r.get(0)?,
                    r.get(1)?,
                    r.get(2)?,
                    r.get(3)?,
                    r.get(4)?,
                    r.get(5)?,
                    r.get(6)?,
                ))
            })?;
            mapped.collect::<Result<Vec<_>, _>>().map_err(Into::into)
        }) {
        Ok(r) => r,
        Err(e) => {
            tracing::warn!(error = %e, "finance recurring scan failed");
            return;
        }
    };

    if rows.is_empty() {
        return;
    }

    let mut posted = 0usize;
    for (id, account_id, title, amount, cadence, next_due, category) in rows {
        let Some(account_id) = account_id.filter(|a| !a.is_empty()) else {
            tracing::warn!(recurring_id = %id, "finance recurring skipped: missing account");
            continue;
        };

        let tx_id = Uuid::new_v4().to_string();
        let posted_at = Utc::now().to_rfc3339();
        let next = advance_next_due(&cadence, &next_due).unwrap_or(next_due);

        let ok = state
            .db
            .with_conn(|conn| {
                conn.execute(
                    "INSERT INTO finance_transaction
                     (id, account_id, posted_at, amount, payee, category, memo, external_id)
                     VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)",
                    rusqlite::params![
                        tx_id,
                        account_id,
                        posted_at,
                        amount,
                        title,
                        category,
                        "recurring",
                        id
                    ],
                )?;
                conn.execute(
                    "UPDATE finance_account SET balance = balance + ?1 WHERE id = ?2",
                    rusqlite::params![amount, account_id],
                )?;
                conn.execute(
                    "UPDATE finance_recurring SET next_due = ?1 WHERE id = ?2",
                    rusqlite::params![next, id],
                )?;
                Ok(())
            })
            .is_ok();

        if ok {
            posted += 1;
        }
    }

    if posted > 0 {
        tracing::info!(posted, "finance recurring transactions posted");
        if let Ok(rev) = state.db.bump_revision("finance") {
            let _ = app.emit(
                "db:change",
                DbChangeEvent {
                    domain: "finance".to_string(),
                    revision: rev,
                },
            );
        }
    }
}

async fn discovery_federal_sync_stub() {
    let url = "https://api.data.gov/ed/collegescorecard/v1/schools?fields=id,school.name,school.city,school.state&per_page=1";
    match reqwest::Client::new().get(url).send().await {
        Ok(resp) if resp.status().is_success() => {
            tracing::info!(
                status = %resp.status(),
                "discovery federal sync: College Scorecard API reachable (stub — no import)"
            );
        }
        Ok(resp) => {
            tracing::info!(
                status = %resp.status(),
                "discovery federal sync: API responded but import not configured"
            );
        }
        Err(e) => {
            tracing::info!(error = %e, "discovery federal sync: no-op (API unavailable)");
        }
    }
}

fn link_calendar_events(app: &AppHandle, state: &AppState) {
    use std::collections::HashMap;

    let result = state.db.with_conn(|conn| {
        let mut course_by_code: HashMap<String, (String, String)> = HashMap::new();
        {
            let mut stmt =
                conn.prepare("SELECT id, semester_id, UPPER(code) FROM planner_course")?;
            let rows = stmt.query_map([], |r| {
                Ok((
                    r.get::<_, String>(2)?,
                    (r.get::<_, String>(0)?, r.get::<_, String>(1)?),
                ))
            })?;
            for row in rows {
                let (code, pair) = row?;
                course_by_code.entry(code).or_insert(pair);
            }
        }

        let mut stmt = conn.prepare(
            "SELECT id, title FROM calendar_event
             WHERE (course_id IS NULL OR course_id = '') AND title != ''",
        )?;
        let events: Vec<(String, String)> = stmt
            .query_map([], |r| Ok((r.get(0)?, r.get(1)?)))?
            .collect::<Result<Vec<_>, _>>()?;

        let now = Utc::now().to_rfc3339();
        let mut linked = 0usize;
        for (event_id, title) in events {
            let Some(code) = extract_course_code(&title) else {
                continue;
            };
            let Some((course_id, semester_id)) = course_by_code.get(&code) else {
                continue;
            };
            conn.execute(
                "UPDATE calendar_event SET course_id = ?1, semester_id = ?2, updated_at = ?3
                 WHERE id = ?4",
                rusqlite::params![course_id, semester_id, now, event_id],
            )?;
            linked += 1;
        }
        Ok(linked)
    });

    let linked = match result {
        Ok(n) => n,
        Err(e) => {
            tracing::warn!(error = %e, "calendar course linker query failed");
            return;
        }
    };

    if linked > 0 {
        tracing::info!(linked, "calendar course linker updated events");
        if let Ok(rev) = state.db.bump_revision("calendar") {
            let _ = app.emit(
                "db:change",
                DbChangeEvent {
                    domain: "calendar".to_string(),
                    revision: rev,
                },
            );
        }
    }
}

async fn coinbase_daily_sync(app: &AppHandle) {
    let Some(state) = app.try_state::<AppState>() else {
        return;
    };
    let api_key = state
        .inner()
        .db
        .get_setting(COINBASE_API_KEY_SETTING)
        .ok()
        .flatten()
        .unwrap_or_default();
    if api_key.trim().is_empty() {
        return;
    }

    let result = finance_connections::run_coinbase_sync(state.inner()).await;
    tracing::info!(
        accounts = result.accounts_updated,
        holdings = result.holdings_updated,
        error = ?result.error,
        "Coinbase daily sync finished"
    );
    if result.accounts_updated > 0 || result.holdings_updated > 0 {
        if let Ok(rev) = state.inner().db.bump_revision("finance") {
            let _ = app.emit(
                "db:change",
                DbChangeEvent {
                    domain: "finance".into(),
                    revision: rev,
                },
            );
        }
    }
}

pub fn spawn(app: AppHandle) {
    // Finance recurring — every 6 hours.
    {
        let app = app.clone();
        tauri::async_runtime::spawn(async move {
            loop {
                if let Some(state) = app.try_state::<AppState>() {
                    post_due_recurring(&app, state.inner());
                }
                tokio::time::sleep(FINANCE_INTERVAL).await;
            }
        });
    }

    // Discovery federal sync — monthly stub.
    {
        tauri::async_runtime::spawn(async move {
            discovery_federal_sync_stub().await;
            loop {
                tokio::time::sleep(DISCOVERY_INTERVAL).await;
                discovery_federal_sync_stub().await;
            }
        });
    }

    // Calendar course linker — daily.
    {
        let app = app.clone();
        tauri::async_runtime::spawn(async move {
            tokio::time::sleep(std::time::Duration::from_secs(60)).await;
            loop {
                if let Some(state) = app.try_state::<AppState>() {
                    link_calendar_events(&app, state.inner());
                }
                tokio::time::sleep(CALENDAR_LINKER_INTERVAL).await;
            }
        });
    }

    // Coinbase sync — daily when API key configured.
    {
        let app = app.clone();
        tauri::async_runtime::spawn(async move {
            tokio::time::sleep(std::time::Duration::from_secs(120)).await;
            loop {
                coinbase_daily_sync(&app).await;
                tokio::time::sleep(COINBASE_SYNC_INTERVAL).await;
            }
        });
    }
}
