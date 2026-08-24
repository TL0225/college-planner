//! Coinbase connection sync — spot prices for holdings and optional account import.

use crate::commands::CmdResult;
use crate::db::DbChangeEvent;
use crate::AppState;
use chrono::Utc;
use serde::Deserialize;
use serde::Serialize;
use tauri::{AppHandle, Emitter, State};

const COINBASE_API: &str = "https://api.coinbase.com";
pub const COINBASE_API_KEY_SETTING: &str = "finance.coinbase.apiKey";
pub const COINBASE_LAST_SYNC_KEY: &str = "finance.coinbase.lastSyncAt";

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CoinbaseSyncResult {
    pub accounts_updated: i64,
    pub holdings_updated: i64,
    pub error: Option<String>,
}

#[derive(Debug, Deserialize)]
struct CoinbaseAccountsResponse {
    data: Vec<CoinbaseAccount>,
}

#[derive(Debug, Deserialize)]
struct CoinbaseAccount {
    id: String,
    name: String,
    balance: CoinbaseMoney,
    currency: CoinbaseCurrency,
    #[serde(rename = "type")]
    account_type: String,
}

#[derive(Debug, Deserialize)]
struct CoinbaseMoney {
    amount: String,
}

#[derive(Debug, Deserialize)]
struct CoinbaseCurrency {
    code: String,
}

#[derive(Debug, Deserialize)]
struct CoinbaseSpotResponse {
    data: CoinbaseMoney,
}

fn coinbase_client() -> reqwest::Client {
    reqwest::Client::builder()
        .user_agent("College/1.0")
        .build()
        .unwrap_or_else(|_| reqwest::Client::new())
}

async fn fetch_accounts_bearer(api_key: &str) -> Result<Vec<CoinbaseAccount>, String> {
    let resp = coinbase_client()
        .get(format!("{COINBASE_API}/v2/accounts?limit=100"))
        .header("Authorization", format!("Bearer {api_key}"))
        .header("CB-VERSION", "2019-12-06")
        .send()
        .await
        .map_err(|e| e.to_string())?;
    if !resp.status().is_success() {
        return Err(format!("accounts HTTP {}", resp.status()));
    }
    let body: CoinbaseAccountsResponse = resp.json().await.map_err(|e| e.to_string())?;
    Ok(body.data)
}

async fn fetch_spot_price_usd(symbol: &str) -> Result<f64, String> {
    let pair = format!("{symbol}-USD");
    let url = format!("{COINBASE_API}/v2/prices/{pair}/spot");
    let resp = coinbase_client()
        .get(&url)
        .header("CB-VERSION", "2019-12-06")
        .send()
        .await
        .map_err(|e| e.to_string())?;
    if !resp.status().is_success() {
        return Err(format!("spot HTTP {} for {pair}", resp.status()));
    }
    let body: CoinbaseSpotResponse = resp.json().await.map_err(|e| e.to_string())?;
    body.data
        .amount
        .parse::<f64>()
        .map_err(|e| format!("invalid spot amount: {e}"))
}

fn upsert_coinbase_accounts(state: &AppState, accounts: &[CoinbaseAccount]) -> Result<i64, String> {
    let mut updated = 0i64;
    state
        .db
        .with_conn(|conn| {
            for acct in accounts {
                let balance: f64 = acct.balance.amount.parse().unwrap_or(0.0);
                if balance.abs() < 1e-12 && acct.currency.code != "USD" {
                    continue;
                }
                let id = format!("coinbase:{}", acct.id);
                let account_type = match acct.account_type.as_str() {
                    "wallet" => "crypto",
                    _ => "checking",
                };
                let exists: i64 = conn.query_row(
                    "SELECT COUNT(1) FROM finance_account WHERE id = ?1",
                    rusqlite::params![id],
                    |r| r.get(0),
                )?;
                if exists > 0 {
                    conn.execute(
                        "UPDATE finance_account
                         SET name = ?1, institution = 'Coinbase', account_type = ?2,
                             balance = ?3, currency = ?4
                         WHERE id = ?5",
                        rusqlite::params![
                            acct.name,
                            account_type,
                            balance,
                            acct.currency.code,
                            id
                        ],
                    )?;
                } else {
                    conn.execute(
                        "INSERT INTO finance_account
                         (id, name, institution, account_type, currency, balance, is_hidden, sort_order)
                         VALUES (?1, ?2, 'Coinbase', ?3, ?4, ?5, 0, 0)",
                        rusqlite::params![id, acct.name, account_type, acct.currency.code, balance],
                    )?;
                }
                updated += 1;
            }
            Ok(updated)
        })
        .map_err(|e| e.to_string())
}

fn sync_holding_spot_prices(state: &AppState) -> Result<i64, String> {
    let symbols: Vec<String> = state
        .db
        .with_conn(|conn| {
            let mut stmt = conn.prepare(
                "SELECT DISTINCT UPPER(symbol) FROM finance_holding
                 WHERE symbol != '' AND asset_type IN ('crypto', 'stock', 'etf')",
            )?;
            let rows = stmt
                .query_map([], |r| r.get::<_, String>(0))?
                .collect::<Result<Vec<_>, _>>()?;
            Ok(rows)
        })
        .map_err(|e| e.to_string())?;

    if symbols.is_empty() {
        // Default crypto symbols when no holdings yet.
        return Ok(0);
    }

    let now = Utc::now().to_rfc3339();
    let mut updated = 0i64;
    let mut last_err: Option<String> = None;

    for symbol in symbols {
        let price = match tauri::async_runtime::block_on(fetch_spot_price_usd(&symbol)) {
            Ok(p) => p,
            Err(e) => {
                last_err = Some(e);
                continue;
            }
        };
        let ok = state
            .db
            .with_conn(|conn| {
                conn.execute(
                    "UPDATE finance_holding SET price_per_unit = ?1, updated_at = ?2
                     WHERE UPPER(symbol) = ?3",
                    rusqlite::params![price, now, symbol],
                )?;
                Ok(())
            })
            .is_ok();
        if ok {
            updated += 1;
        }
    }

    if updated == 0 {
        if let Some(e) = last_err {
            return Err(e);
        }
    }
    Ok(updated)
}

/// Core Coinbase sync — public spot prices plus optional bearer-token account import.
pub async fn run_coinbase_sync(state: &AppState) -> CoinbaseSyncResult {
    let api_key = state
        .db
        .get_setting(COINBASE_API_KEY_SETTING)
        .ok()
        .flatten()
        .unwrap_or_default();

    let mut accounts_updated = 0i64;
    let mut error: Option<String> = None;

    if !api_key.trim().is_empty() {
        match fetch_accounts_bearer(api_key.trim()).await {
            Ok(accounts) => match upsert_coinbase_accounts(state, &accounts) {
                Ok(n) => accounts_updated = n,
                Err(e) => error = Some(format!("accounts persist: {e}")),
            },
            Err(e) => {
                tracing::info!(error = %e, "Coinbase account import skipped; continuing with spot prices");
                error = Some(format!("accounts: {e}"));
            }
        }
    }

    let holdings_updated = match sync_holding_spot_prices(state) {
        Ok(n) => n,
        Err(e) => {
            if error.is_none() {
                error = Some(format!("holdings: {e}"));
            }
            0
        }
    };

    let now = Utc::now().to_rfc3339();
    let _ = state.db.set_setting(COINBASE_LAST_SYNC_KEY, &now);

    CoinbaseSyncResult {
        accounts_updated,
        holdings_updated,
        error,
    }
}

#[tauri::command]
pub async fn finance_sync_coinbase(
    app: AppHandle,
    state: State<'_, AppState>,
) -> CmdResult<CoinbaseSyncResult> {
    let result = run_coinbase_sync(state.inner()).await;
    if result.accounts_updated > 0 || result.holdings_updated > 0 {
        if let Ok(rev) = state.db.bump_revision("finance") {
            let _ = app.emit(
                "db:change",
                DbChangeEvent {
                    domain: "finance".into(),
                    revision: rev,
                },
            );
        }
    }
    Ok(result)
}
