use crate::commands::CmdResult;
use crate::AppState;
use serde::Serialize;
use tauri::State;

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct FinanceAccountDto {
    pub id: String,
    pub name: String,
    pub institution: String,
    pub account_type: String,
    pub balance: f64,
    pub currency: String,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct FinanceDashboardSummary {
    pub net_worth: f64,
    pub account_balance_total: f64,
    pub holdings_value: f64,
    pub account_count: i64,
    pub transaction_count: i64,
    pub budget_count: i64,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct FinanceTransactionDto {
    pub id: String,
    pub account_id: String,
    pub account_name: String,
    pub posted_at: String,
    pub amount: f64,
    pub payee: String,
    pub category: String,
    pub memo: String,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct FinanceBudgetDto {
    pub id: String,
    pub name: String,
    pub category: String,
    pub amount: f64,
    pub period: String,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct FinanceGoalDto {
    pub id: String,
    pub name: String,
    pub target_amount: f64,
    pub current_amount: f64,
    pub deadline: Option<String>,
    pub notes: String,
    pub sort_order: i64,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct FinanceInventoryItemDto {
    pub id: String,
    pub name: String,
    pub category: String,
    pub purchase_date: Option<String>,
    pub value: f64,
    pub notes: String,
    pub sort_order: i64,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct FinanceReceiptDto {
    pub id: String,
    pub title: String,
    pub merchant: String,
    pub amount: f64,
    pub purchased_at: Option<String>,
    pub category: String,
    pub notes: String,
    pub vault_doc_id: Option<String>,
    pub sort_order: i64,
}

#[tauri::command]
pub fn finance_list_accounts(state: State<'_, AppState>) -> CmdResult<Vec<FinanceAccountDto>> {
    state
        .db
        .with_conn(|conn| {
            let mut stmt = conn.prepare(
                "SELECT id, name, institution, account_type, balance, currency
                 FROM finance_account WHERE is_hidden = 0
                 ORDER BY sort_order ASC, name ASC",
            )?;
            let rows = stmt
                .query_map([], |r| {
                    Ok(FinanceAccountDto {
                        id: r.get(0)?,
                        name: r.get(1)?,
                        institution: r.get(2)?,
                        account_type: r.get(3)?,
                        balance: r.get(4)?,
                        currency: r.get(5)?,
                    })
                })?
                .collect::<Result<Vec<_>, _>>()?;
            Ok(rows)
        })
        .map_err(Into::into)
}

#[tauri::command]
pub fn finance_list_transactions(
    state: State<'_, AppState>,
    account_id: Option<String>,
    limit: Option<i64>,
) -> CmdResult<Vec<FinanceTransactionDto>> {
    let limit = limit.unwrap_or(100).clamp(1, 500);
    state
        .db
        .with_conn(|conn| {
            let mut rows = Vec::new();
            if let Some(aid) = account_id {
                let mut stmt = conn.prepare(
                    "SELECT t.id, t.account_id, a.name, t.posted_at, t.amount, t.payee, t.category, t.memo
                     FROM finance_transaction t
                     JOIN finance_account a ON a.id = t.account_id
                     WHERE t.account_id = ?1
                     ORDER BY t.posted_at DESC
                     LIMIT ?2",
                )?;
                let mapped = stmt.query_map(rusqlite::params![aid, limit], |r| {
                    Ok(FinanceTransactionDto {
                        id: r.get(0)?,
                        account_id: r.get(1)?,
                        account_name: r.get(2)?,
                        posted_at: r.get(3)?,
                        amount: r.get(4)?,
                        payee: r.get(5)?,
                        category: r.get(6)?,
                        memo: r.get(7)?,
                    })
                })?;
                for row in mapped {
                    rows.push(row?);
                }
            } else {
                let mut stmt = conn.prepare(
                    "SELECT t.id, t.account_id, a.name, t.posted_at, t.amount, t.payee, t.category, t.memo
                     FROM finance_transaction t
                     JOIN finance_account a ON a.id = t.account_id
                     ORDER BY t.posted_at DESC
                     LIMIT ?1",
                )?;
                let mapped = stmt.query_map(rusqlite::params![limit], |r| {
                    Ok(FinanceTransactionDto {
                        id: r.get(0)?,
                        account_id: r.get(1)?,
                        account_name: r.get(2)?,
                        posted_at: r.get(3)?,
                        amount: r.get(4)?,
                        payee: r.get(5)?,
                        category: r.get(6)?,
                        memo: r.get(7)?,
                    })
                })?;
                for row in mapped {
                    rows.push(row?);
                }
            }
            Ok(rows)
        })
        .map_err(Into::into)
}

#[tauri::command]
pub fn finance_list_goals(state: State<'_, AppState>) -> CmdResult<Vec<FinanceGoalDto>> {
    state
        .db
        .with_conn(|conn| {
            let mut stmt = conn.prepare(
                "SELECT id, name, target_amount, current_amount, deadline, notes, sort_order
                 FROM finance_goal ORDER BY sort_order ASC, name ASC LIMIT 200",
            )?;
            let rows = stmt
                .query_map([], |r| {
                    Ok(FinanceGoalDto {
                        id: r.get(0)?,
                        name: r.get(1)?,
                        target_amount: r.get(2)?,
                        current_amount: r.get(3)?,
                        deadline: r.get(4)?,
                        notes: r.get(5)?,
                        sort_order: r.get(6)?,
                    })
                })?
                .collect::<Result<Vec<_>, _>>()?;
            Ok(rows)
        })
        .map_err(Into::into)
}

#[tauri::command]
pub fn finance_list_inventory_items(
    state: State<'_, AppState>,
) -> CmdResult<Vec<FinanceInventoryItemDto>> {
    state
        .db
        .with_conn(|conn| {
            let mut stmt = conn.prepare(
                "SELECT id, name, category, purchase_date, value, notes, sort_order
                 FROM finance_inventory_item ORDER BY sort_order ASC, name ASC LIMIT 500",
            )?;
            let rows = stmt
                .query_map([], |r| {
                    Ok(FinanceInventoryItemDto {
                        id: r.get(0)?,
                        name: r.get(1)?,
                        category: r.get(2)?,
                        purchase_date: r.get(3)?,
                        value: r.get(4)?,
                        notes: r.get(5)?,
                        sort_order: r.get(6)?,
                    })
                })?
                .collect::<Result<Vec<_>, _>>()?;
            Ok(rows)
        })
        .map_err(Into::into)
}

#[tauri::command]
pub fn finance_list_receipts(state: State<'_, AppState>) -> CmdResult<Vec<FinanceReceiptDto>> {
    state
        .db
        .with_conn(|conn| {
            let mut stmt = conn.prepare(
                "SELECT id, title, merchant, amount, purchased_at, category, notes, vault_doc_id, sort_order
                 FROM finance_receipt ORDER BY sort_order ASC, purchased_at DESC LIMIT 500",
            )?;
            let rows = stmt
                .query_map([], |r| {
                    Ok(FinanceReceiptDto {
                        id: r.get(0)?,
                        title: r.get(1)?,
                        merchant: r.get(2)?,
                        amount: r.get(3)?,
                        purchased_at: r.get(4)?,
                        category: r.get(5)?,
                        notes: r.get(6)?,
                        vault_doc_id: r.get(7)?,
                        sort_order: r.get(8)?,
                    })
                })?
                .collect::<Result<Vec<_>, _>>()?;
            Ok(rows)
        })
        .map_err(Into::into)
}

#[tauri::command]
pub fn finance_list_budgets(state: State<'_, AppState>) -> CmdResult<Vec<FinanceBudgetDto>> {
    state
        .db
        .with_conn(|conn| {
            let mut stmt = conn.prepare(
                "SELECT id, name, category, amount, period
                 FROM finance_budget ORDER BY name ASC LIMIT 200",
            )?;
            let rows = stmt
                .query_map([], |r| {
                    Ok(FinanceBudgetDto {
                        id: r.get(0)?,
                        name: r.get(1)?,
                        category: r.get(2)?,
                        amount: r.get(3)?,
                        period: r.get(4)?,
                    })
                })?
                .collect::<Result<Vec<_>, _>>()?;
            Ok(rows)
        })
        .map_err(Into::into)
}

#[tauri::command]
pub fn finance_dashboard_summary(state: State<'_, AppState>) -> CmdResult<FinanceDashboardSummary> {
    state
        .db
        .with_conn(|conn| {
            let account_balance_total: f64 = conn
                .query_row(
                    "SELECT COALESCE(SUM(balance), 0) FROM finance_account WHERE is_hidden = 0",
                    [],
                    |r| r.get(0),
                )
                .unwrap_or(0.0);
            let holdings_value: f64 = conn
                .query_row(
                    "SELECT COALESCE(SUM(quantity * price_per_unit), 0) FROM finance_holding",
                    [],
                    |r| r.get(0),
                )
                .unwrap_or(0.0);
            let net_worth = account_balance_total + holdings_value;
            let account_count: i64 = conn
                .query_row("SELECT COUNT(*) FROM finance_account", [], |r| r.get(0))
                .unwrap_or(0);
            let transaction_count: i64 = conn
                .query_row("SELECT COUNT(*) FROM finance_transaction", [], |r| r.get(0))
                .unwrap_or(0);
            let budget_count: i64 = conn
                .query_row("SELECT COUNT(*) FROM finance_budget", [], |r| r.get(0))
                .unwrap_or(0);
            Ok(FinanceDashboardSummary {
                net_worth,
                account_balance_total,
                holdings_value,
                account_count,
                transaction_count,
                budget_count,
            })
        })
        .map_err(Into::into)
}

#[tauri::command]
pub fn finance_export_transactions_csv(
    state: State<'_, AppState>,
    account_id: Option<String>,
) -> CmdResult<String> {
    state.db.with_conn(|conn| {
        let mut out = String::from("date,amount,payee,category,account,memo\n");
        let mut push_row = |posted: String,
                            amount: f64,
                            payee: String,
                            category: String,
                            account: String,
                            memo: String| {
            let esc = |s: &str| {
                if s.contains(',') || s.contains('"') || s.contains('\n') {
                    format!("\"{}\"", s.replace('"', "\"\""))
                } else {
                    s.to_string()
                }
            };
            out.push_str(&format!(
                "{},{},{},{},{},{}\n",
                esc(&posted),
                amount,
                esc(&payee),
                esc(&category),
                esc(&account),
                esc(&memo)
            ));
        };
        if let Some(aid) = account_id.filter(|s| !s.is_empty()) {
            let mut stmt = conn.prepare(
                "SELECT t.posted_at, t.amount, t.payee, t.category, a.name, t.memo
                 FROM finance_transaction t
                 JOIN finance_account a ON a.id = t.account_id
                 WHERE t.account_id = ?1
                 ORDER BY t.posted_at DESC LIMIT 2000",
            )?;
            let rows = stmt.query_map(rusqlite::params![aid], |r| {
                Ok((
                    r.get::<_, String>(0)?,
                    r.get::<_, f64>(1)?,
                    r.get::<_, String>(2)?,
                    r.get::<_, String>(3)?,
                    r.get::<_, String>(4)?,
                    r.get::<_, String>(5)?,
                ))
            })?;
            for row in rows {
                let (p, a, payee, cat, acct, memo) = row?;
                push_row(p, a, payee, cat, acct, memo);
            }
        } else {
            let mut stmt = conn.prepare(
                "SELECT t.posted_at, t.amount, t.payee, t.category, a.name, t.memo
                 FROM finance_transaction t
                 JOIN finance_account a ON a.id = t.account_id
                 ORDER BY t.posted_at DESC LIMIT 2000",
            )?;
            let rows = stmt.query_map([], |r| {
                Ok((
                    r.get::<_, String>(0)?,
                    r.get::<_, f64>(1)?,
                    r.get::<_, String>(2)?,
                    r.get::<_, String>(3)?,
                    r.get::<_, String>(4)?,
                    r.get::<_, String>(5)?,
                ))
            })?;
            for row in rows {
                let (p, a, payee, cat, acct, memo) = row?;
                push_row(p, a, payee, cat, acct, memo);
            }
        }
        Ok(out)
    })
    .map_err(Into::into)
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ExportCsvPathResult {
    pub path: String,
    pub row_count: i64,
}

#[tauri::command]
pub fn finance_export_transactions_csv_path(
    state: State<'_, AppState>,
    path: String,
    account_id: Option<String>,
) -> CmdResult<ExportCsvPathResult> {
    let csv = finance_export_transactions_csv(state, account_id)?;
    let row_count = csv.lines().count().saturating_sub(1) as i64;
    if let Some(parent) = std::path::Path::new(&path).parent() {
        std::fs::create_dir_all(parent).map_err(anyhow::Error::from)?;
    }
    std::fs::write(&path, &csv).map_err(anyhow::Error::from)?;
    Ok(ExportCsvPathResult { path, row_count })
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct FinanceHoldingDto {
    pub id: String,
    pub asset_type: String,
    pub symbol: String,
    pub name: String,
    pub quantity: f64,
    pub price_per_unit: f64,
    pub market_value: f64,
}

#[tauri::command]
pub fn finance_list_holdings(state: State<'_, AppState>) -> CmdResult<Vec<FinanceHoldingDto>> {
    state
        .db
        .with_conn(|conn| {
            let mut stmt = conn.prepare(
                "SELECT id, asset_type, symbol, name, quantity, price_per_unit
                 FROM finance_holding
                 ORDER BY asset_type ASC, symbol ASC",
            )?;
            let rows = stmt
                .query_map([], |r| {
                    let quantity: f64 = r.get(4)?;
                    let price: f64 = r.get(5)?;
                    Ok(FinanceHoldingDto {
                        id: r.get(0)?,
                        asset_type: r.get(1)?,
                        symbol: r.get(2)?,
                        name: r.get(3)?,
                        quantity,
                        price_per_unit: price,
                        market_value: quantity * price,
                    })
                })?
                .collect::<Result<Vec<_>, _>>()?;
            Ok(rows)
        })
        .map_err(Into::into)
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct FinanceCategoryDto {
    pub id: String,
    pub name: String,
    pub kind: String,
    pub sort_order: i64,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct FinanceRecurringDto {
    pub id: String,
    pub account_id: Option<String>,
    pub account_name: String,
    pub title: String,
    pub amount: f64,
    pub cadence: String,
    pub next_due: Option<String>,
    pub category: String,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct FinanceDueDto {
    pub id: String,
    pub person: String,
    pub amount: f64,
    pub due_at: String,
    pub is_paid: bool,
    pub notes: String,
}

#[tauri::command]
pub fn finance_list_categories(state: State<'_, AppState>) -> CmdResult<Vec<FinanceCategoryDto>> {
    state
        .db
        .with_conn(|conn| {
            let mut stmt = conn.prepare(
                "SELECT id, name, kind, sort_order FROM finance_category ORDER BY sort_order, name",
            )?;
            let rows = stmt
                .query_map([], |r| {
                    Ok(FinanceCategoryDto {
                        id: r.get(0)?,
                        name: r.get(1)?,
                        kind: r.get(2)?,
                        sort_order: r.get(3)?,
                    })
                })?
                .collect::<Result<Vec<_>, _>>()?;
            Ok(rows)
        })
        .map_err(Into::into)
}

#[tauri::command]
pub fn finance_list_recurring(state: State<'_, AppState>) -> CmdResult<Vec<FinanceRecurringDto>> {
    state
        .db
        .with_conn(|conn| {
            let mut stmt = conn.prepare(
                "SELECT r.id, r.account_id, COALESCE(a.name, ''), r.title, r.amount, r.cadence,
                        r.next_due, r.category
                 FROM finance_recurring r
                 LEFT JOIN finance_account a ON a.id = r.account_id
                 ORDER BY r.next_due ASC, r.title ASC
                 LIMIT 200",
            )?;
            let rows = stmt
                .query_map([], |r| {
                    Ok(FinanceRecurringDto {
                        id: r.get(0)?,
                        account_id: r.get(1)?,
                        account_name: r.get(2)?,
                        title: r.get(3)?,
                        amount: r.get(4)?,
                        cadence: r.get(5)?,
                        next_due: r.get(6)?,
                        category: r.get(7)?,
                    })
                })?
                .collect::<Result<Vec<_>, _>>()?;
            Ok(rows)
        })
        .map_err(Into::into)
}

#[tauri::command]
pub fn finance_list_due(state: State<'_, AppState>) -> CmdResult<Vec<FinanceDueDto>> {
    state
        .db
        .with_conn(|conn| {
            let mut stmt = conn.prepare(
                "SELECT id, person, amount, due_at, is_paid, notes
                 FROM finance_due ORDER BY is_paid ASC, due_at ASC LIMIT 200",
            )?;
            let rows = stmt
                .query_map([], |r| {
                    Ok(FinanceDueDto {
                        id: r.get(0)?,
                        person: r.get(1)?,
                        amount: r.get(2)?,
                        due_at: r.get(3)?,
                        is_paid: r.get::<_, i64>(4)? != 0,
                        notes: r.get(5)?,
                    })
                })?
                .collect::<Result<Vec<_>, _>>()?;
            Ok(rows)
        })
        .map_err(Into::into)
}
