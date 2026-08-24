//! Full-table mirror from attached Swift GRDB databases into the Tauri store.

use rusqlite::Connection;
use std::collections::HashSet;

#[derive(Debug, Default)]
pub struct MirrorReport {
    pub tables: i64,
    pub rows: i64,
}

const SKIP_PREFIXES: &[&str] = &[
    "sqlite_",
    "grdb_",
    "Z_",
    "ZPRIMARY",
    "ZMETADATA",
    "ZMODEL",
    "ATRANS",
    "ACHANGE",
];

pub fn should_mirror_table(name: &str) -> bool {
    if name.starts_with('_') {
        return false;
    }
    if name == "schema_migrations" || name == "college_metadata" {
        return false;
    }
    if name.starts_with('Z') && name != "ZPROFILE" {
        return false;
    }
    !SKIP_PREFIXES.iter().any(|p| name.starts_with(p))
}

fn table_columns(conn: &Connection, schema: &str, table: &str) -> rusqlite::Result<Vec<String>> {
    let sql = if schema.is_empty() {
        format!("PRAGMA table_info({table})")
    } else {
        format!("PRAGMA {schema}.table_info({table})")
    };
    let mut stmt = conn.prepare(&sql)?;
    let mut rows = stmt.query([])?;
    let mut cols = Vec::new();
    while let Some(row) = rows.next()? {
        cols.push(row.get(1)?);
    }
    Ok(cols)
}

fn dest_table_exists(conn: &Connection, table: &str) -> rusqlite::Result<bool> {
    let n: i64 = conn.query_row(
        "SELECT COUNT(1) FROM sqlite_master WHERE type = 'table' AND name = ?1",
        rusqlite::params![table],
        |r| r.get(0),
    )?;
    Ok(n > 0)
}

fn ensure_dest_table(conn: &Connection, src: &str, table: &str) -> rusqlite::Result<()> {
    if dest_table_exists(conn, table)? {
        return Ok(());
    }
    let sql = format!("CREATE TABLE \"{table}\" AS SELECT * FROM {src}.\"{table}\" WHERE 0");
    conn.execute(&sql, [])?;
    Ok(())
}

fn copy_table_intersection(conn: &Connection, src: &str, table: &str) -> rusqlite::Result<i64> {
    let dest_cols = table_columns(conn, "", table)?;
    let src_cols = table_columns(conn, src, table)?;
    if dest_cols.is_empty() || src_cols.is_empty() {
        return Ok(0);
    }
    let src_set: HashSet<_> = src_cols.iter().collect();
    let common: Vec<String> = dest_cols
        .into_iter()
        .filter(|c| src_set.contains(c))
        .collect();
    if common.is_empty() {
        return Ok(0);
    }
    let cols = common.join(", ");
    let sql = format!(
        "INSERT OR REPLACE INTO \"{table}\" ({cols}) SELECT {cols} FROM {src}.\"{table}\""
    );
    conn.execute(&sql, [])?;
    Ok(conn.changes() as i64)
}

fn copy_table_full(conn: &Connection, src: &str, table: &str) -> rusqlite::Result<i64> {
    ensure_dest_table(conn, src, table)?;
    let cols = table_columns(conn, src, table)?;
    if cols.is_empty() {
        return Ok(0);
    }
    let col_list = cols
        .iter()
        .map(|c| format!("\"{c}\""))
        .collect::<Vec<_>>()
        .join(", ");
    let sql = format!(
        "INSERT OR REPLACE INTO \"{table}\" ({col_list}) SELECT {col_list} FROM {src}.\"{table}\""
    );
    conn.execute(&sql, [])?;
    Ok(conn.changes() as i64)
}

/// Mirror every user table from attached `src` schema into the main database.
pub fn mirror_all_tables(conn: &Connection, src: &str) -> rusqlite::Result<MirrorReport> {
    let mut report = MirrorReport::default();
    let sql = format!("SELECT name FROM {src}.sqlite_master WHERE type = 'table' ORDER BY name");
    let mut stmt = conn.prepare(&sql)?;
    let mut rows = stmt.query([])?;
    while let Some(row) = rows.next()? {
        let table: String = row.get(0)?;
        if !should_mirror_table(&table) {
            continue;
        }
        let copied = if dest_table_exists(conn, &table)? {
            copy_table_intersection(conn, src, &table).unwrap_or(0)
        } else {
            copy_table_full(conn, src, &table).unwrap_or(0)
        };
        if copied > 0 || dest_table_exists(conn, &table)? {
            report.tables += 1;
            report.rows += copied;
        }
    }
    Ok(report)
}

/// Import legacy SwiftData ZPROFILE row into Tauri `profile`.
pub fn import_zprofile(conn: &Connection, src: &str, now: &str) -> rusqlite::Result<i64> {
    let exists: i64 = conn.query_row(
        &format!(
            "SELECT COUNT(1) FROM {src}.sqlite_master WHERE type = 'table' AND name = 'ZPROFILE'"
        ),
        [],
        |r| r.get(0),
    )?;
    if exists == 0 {
        return Ok(0);
    }
    conn.execute(
        &format!(
            "INSERT OR REPLACE INTO profile
             (id, full_name, email, phone, university_name, major, graduation_year, created_at, updated_at)
             SELECT COALESCE(
                      (SELECT id FROM profile LIMIT 1),
                      lower(hex(randomblob(4))) || '-' || lower(hex(randomblob(2))) || '-4' ||
                      substr(lower(hex(randomblob(2))),1,3) || '-' ||
                      substr('89ab', abs(random()) % 4 + 1, 1) || substr(lower(hex(randomblob(2))),1,3) || '-' ||
                      lower(hex(randomblob(6)))
                    ),
                    COALESCE(NULLIF(ZNAME, ''), ''),
                    COALESCE(NULLIF(ZUNIVERSITYEMAIL, ''), ''),
                    COALESCE(NULLIF(ZPERSONALPHONE, ''), ''),
                    COALESCE(NULLIF(ZCOLLEGENAME, ''), ''),
                    '',
                    NULL,
                    ?1, ?1
             FROM {src}.ZPROFILE
             WHERE COALESCE(NULLIF(ZNAME, ''), NULLIF(ZUNIVERSITYEMAIL, ''), NULLIF(ZCOLLEGENAME, '')) IS NOT NULL
             LIMIT 1"
        ),
        rusqlite::params![now],
    )?;
    Ok(conn.changes() as i64)
}

/// Map Swift Finance.sqlite accounts into Tauri finance_account rows.
pub fn import_finance_accounts_swift(conn: &Connection, src: &str) -> rusqlite::Result<i64> {
    let exists: i64 = conn.query_row(
        &format!(
            "SELECT COUNT(1) FROM {src}.sqlite_master WHERE type = 'table' AND name = 'finance_account'"
        ),
        [],
        |r| r.get(0),
    )?;
    if exists == 0 {
        return Ok(0);
    }
    if table_columns(conn, src, "finance_account")
        .map(|c| c.iter().any(|x| x == "accountType"))
        .unwrap_or(false)
    {
        conn.execute(
            &format!(
                "INSERT OR REPLACE INTO finance_account
                 (id, name, institution, account_type, currency, balance, is_hidden, sort_order)
                 SELECT id,
                        COALESCE(name, ''),
                        COALESCE(bankName, ''),
                        COALESCE(accountType, 'checking'),
                        'USD',
                        COALESCE(balance, 0),
                        0,
                        0
                 FROM {src}.finance_account"
            ),
            [],
        )?;
        return Ok(conn.changes() as i64);
    }
    copy_table_intersection(conn, src, "finance_account")
}

/// Map Swift Finance.sqlite transactions into Tauri finance_transaction rows.
pub fn import_finance_transactions_swift(conn: &Connection, src: &str) -> rusqlite::Result<i64> {
    let exists: i64 = conn.query_row(
        &format!(
            "SELECT COUNT(1) FROM {src}.sqlite_master WHERE type = 'table' AND name = 'finance_transaction'"
        ),
        [],
        |r| r.get(0),
    )?;
    if exists == 0 {
        return Ok(0);
    }
    if table_columns(conn, src, "finance_transaction")
        .map(|c| c.iter().any(|x| x == "transactionDate"))
        .unwrap_or(false)
    {
        conn.execute(
            &format!(
                "INSERT OR REPLACE INTO finance_transaction
                 (id, account_id, posted_at, amount, payee, category, memo, external_id)
                 SELECT id,
                        COALESCE(accountID, ''),
                        datetime(COALESCE(transactionDate, 0), 'unixepoch'),
                        COALESCE(amount, 0),
                        COALESCE(title, ''),
                        COALESCE(category, ''),
                        COALESCE(notes, ''),
                        NULL
                 FROM {src}.finance_transaction
                 WHERE accountID IS NOT NULL"
            ),
            [],
        )?;
        return Ok(conn.changes() as i64);
    }
    copy_table_intersection(conn, src, "finance_transaction")
}
