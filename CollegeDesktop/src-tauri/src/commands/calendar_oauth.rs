//! Google + Outlook calendar OAuth (PKCE loopback redirect).
//! Access/refresh tokens live in the platform secret store (Keychain / DPAPI);
//! SQLite keeps account metadata + a `@secure` marker. Refresh is automatic on sync.

use crate::commands::calendar::{bump_calendar, ensure_default_calendar_source};
use crate::commands::CmdResult;
use crate::AppState;
use chrono::{Duration, Utc};
use parking_lot::Mutex;
use rand::RngCore;
use reqwest::Client;
use rusqlite::{Connection, OptionalExtension};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use sha2::{Digest, Sha256};
use std::collections::HashMap;
use std::io::{Read, Write};
use std::net::{TcpListener, TcpStream};
use std::sync::{mpsc, OnceLock};
use std::time::Duration as StdDuration;
use tauri::{AppHandle, State};
use uuid::Uuid;

const OAUTH_CALLBACK_PATH: &str = "/oauth/callback";
const OAUTH_TIMEOUT_SECS: u64 = 120;
const OAUTH_SECRET_NS: &str = "calendar.oauth";
const OAUTH_TOKEN_MARKER: &str = "@secure";

fn oauth_access_key(account_id: &str) -> String {
    format!("{account_id}.access")
}

fn oauth_refresh_key(account_id: &str) -> String {
    format!("{account_id}.refresh")
}

fn is_token_marker(value: &str) -> bool {
    value.is_empty() || value == OAUTH_TOKEN_MARKER
}

fn store_oauth_tokens(state: &AppState, account_id: &str, access: &str, refresh: &str) -> anyhow::Result<()> {
    state
        .security
        .set_secret(OAUTH_SECRET_NS, &oauth_access_key(account_id), access.as_bytes())?;
    state.security.set_secret(
        OAUTH_SECRET_NS,
        &oauth_refresh_key(account_id),
        refresh.as_bytes(),
    )?;
    Ok(())
}

fn clear_oauth_tokens(state: &AppState, account_id: &str) {
    let _ = state
        .security
        .delete_secret(OAUTH_SECRET_NS, &oauth_access_key(account_id));
    let _ = state
        .security
        .delete_secret(OAUTH_SECRET_NS, &oauth_refresh_key(account_id));
}

fn secret_to_string(bytes: Option<Vec<u8>>) -> String {
    bytes
        .and_then(|b| String::from_utf8(b).ok())
        .unwrap_or_default()
}

/// Load tokens from Keychain/DPAPI; migrate legacy SQLite plaintext once.
fn load_oauth_tokens(
    state: &AppState,
    account_id: &str,
) -> anyhow::Result<(String, String, String, Option<String>)> {
    let (provider, access_db, refresh_db, expires_at): (String, String, String, Option<String>) =
        state.db.with_conn(|conn| {
            conn.query_row(
                "SELECT provider, access_token_enc, refresh_token_enc, expires_at
                 FROM calendar_oauth_account WHERE id = ?1",
                rusqlite::params![account_id],
                |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?)),
            )
            .map_err(Into::into)
        })?;

    let mut access = secret_to_string(
        state
            .security
            .get_secret(OAUTH_SECRET_NS, &oauth_access_key(account_id))?,
    );
    let mut refresh = secret_to_string(
        state
            .security
            .get_secret(OAUTH_SECRET_NS, &oauth_refresh_key(account_id))?,
    );

    let legacy_access = !is_token_marker(&access_db);
    let legacy_refresh = !is_token_marker(&refresh_db);
    if legacy_access || legacy_refresh {
        if access.is_empty() && legacy_access {
            access = access_db.clone();
        }
        if refresh.is_empty() && legacy_refresh {
            refresh = refresh_db.clone();
        }
        let _ = store_oauth_tokens(state, account_id, &access, &refresh);
        let _ = state.db.with_conn(|conn| {
            conn.execute(
                "UPDATE calendar_oauth_account
                 SET access_token_enc = ?1, refresh_token_enc = ?2, updated_at = ?3
                 WHERE id = ?4",
                rusqlite::params![
                    OAUTH_TOKEN_MARKER,
                    OAUTH_TOKEN_MARKER,
                    Utc::now().to_rfc3339(),
                    account_id
                ],
            )?;
            Ok(())
        });
    }

    Ok((provider, access, refresh, expires_at))
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CalendarOAuthBeginResult {
    pub auth_url: String,
    pub state: String,
    pub redirect_uri: String,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CalendarOAuthAccountDto {
    pub id: String,
    pub provider: String,
    pub account_email: String,
    pub source_id: Option<String>,
    pub scopes: String,
    pub expires_at: Option<String>,
    pub last_synced_at: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CalendarOAuthStatus {
    pub accounts: Vec<CalendarOAuthAccountDto>,
    pub google_configured: bool,
    pub outlook_configured: bool,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CalendarOAuthSyncResult {
    pub imported: i64,
    pub skipped: i64,
    pub last_synced_at: String,
}

#[derive(Debug, Deserialize)]
struct TokenResponse {
    access_token: String,
    refresh_token: Option<String>,
    expires_in: Option<i64>,
    scope: Option<String>,
}

struct PendingOAuth {
    provider: String,
    code_verifier: String,
    redirect_uri: String,
    code_rx: mpsc::Receiver<Result<String, String>>,
}

struct OAuthSessions {
    inner: Mutex<HashMap<String, PendingOAuth>>,
}

impl OAuthSessions {
    fn global() -> &'static OAuthSessions {
        static SESSIONS: OnceLock<OAuthSessions> = OnceLock::new();
        SESSIONS.get_or_init(|| OAuthSessions {
            inner: Mutex::new(HashMap::new()),
        })
    }
}

fn url_encode(value: &str) -> String {
    let mut out = String::with_capacity(value.len());
    for byte in value.bytes() {
        match byte {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => {
                out.push(byte as char);
            }
            _ => out.push_str(&format!("%{byte:02X}")),
        }
    }
    out
}

fn base64url_no_pad(bytes: &[u8]) -> String {
    use base64::Engine;
    base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(bytes)
}

fn generate_pkce_pair() -> (String, String) {
    let mut verifier_bytes = [0u8; 32];
    rand::thread_rng().fill_bytes(&mut verifier_bytes);
    let verifier = base64url_no_pad(&verifier_bytes);
    let challenge = base64url_no_pad(&Sha256::digest(verifier.as_bytes()));
    (verifier, challenge)
}

fn pick_loopback_listener() -> anyhow::Result<(TcpListener, u16)> {
    let listener = TcpListener::bind("127.0.0.1:0")?;
    let port = listener.local_addr()?.port();
    Ok((listener, port))
}

fn percent_decode(s: &str) -> String {
    let mut out = String::new();
    let mut chars = s.chars();
    while let Some(c) = chars.next() {
        if c == '%' {
            let a = chars.next();
            let b = chars.next();
            if let (Some(a), Some(b)) = (a, b) {
                if let Ok(byte) = u8::from_str_radix(&format!("{a}{b}"), 16) {
                    out.push(byte as char);
                    continue;
                }
            }
            out.push('%');
            if let Some(a) = a {
                out.push(a);
            }
            if let Some(b) = b {
                out.push(b);
            }
        } else if c == '+' {
            out.push(' ');
        } else {
            out.push(c);
        }
    }
    out
}

fn parse_query_param(query: &str, key: &str) -> Option<String> {
    for pair in query.split('&') {
        let mut parts = pair.splitn(2, '=');
        let k = parts.next()?;
        if k == key {
            return Some(percent_decode(parts.next().unwrap_or("")));
        }
    }
    None
}

fn read_http_request(stream: &mut TcpStream) -> anyhow::Result<(String, String)> {
    stream.set_read_timeout(Some(StdDuration::from_secs(30)))?;
    let mut buf = [0u8; 4096];
    let n = stream.read(&mut buf)?;
    let req = String::from_utf8_lossy(&buf[..n]);
    let request_line = req.lines().next().unwrap_or("");
    let mut parts = request_line.split_whitespace();
    let _method = parts.next().unwrap_or("");
    let path = parts.next().unwrap_or("");
    let (path_only, query) = match path.split_once('?') {
        Some((p, q)) => (p, q),
        None => (path, ""),
    };
    Ok((path_only.to_string(), query.to_string()))
}

fn write_oauth_response(stream: &mut TcpStream, success: bool) -> anyhow::Result<()> {
    let body = if success {
        "<html><body><h2>College</h2><p>Calendar connected. You can close this tab.</p></body></html>"
    } else {
        "<html><body><h2>College</h2><p>Connection failed. Return to the app and try again.</p></body></html>"
    };
    let response = format!(
        "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
        body.len(),
        body
    );
    stream.write_all(response.as_bytes())?;
    stream.flush()?;
    Ok(())
}

fn spawn_callback_listener(
    listener: TcpListener,
    state: String,
    result_tx: mpsc::Sender<Result<String, String>>,
) {
    std::thread::spawn(move || {
        if let Ok((mut stream, _)) = listener.accept() {
            let result = (|| -> Result<String, String> {
                let (path, query) = read_http_request(&mut stream).map_err(|e| e.to_string())?;
                if path != OAUTH_CALLBACK_PATH {
                    write_oauth_response(&mut stream, false).ok();
                    return Err("Unexpected OAuth callback path".into());
                }
                if let Some(err) = parse_query_param(&query, "error") {
                    write_oauth_response(&mut stream, false).ok();
                    return Err(format!("OAuth denied: {err}"));
                }
                let returned_state = parse_query_param(&query, "state")
                    .ok_or_else(|| "Missing state".to_string())?;
                if returned_state != state {
                    write_oauth_response(&mut stream, false).ok();
                    return Err("OAuth state mismatch".into());
                }
                let code = parse_query_param(&query, "code")
                    .ok_or_else(|| "Missing authorization code".to_string())?;
                write_oauth_response(&mut stream, true).map_err(|e| e.to_string())?;
                Ok(code)
            })();
            let _ = result_tx.send(result);
        }
    });
}

fn oauth_setting(state: &State<'_, AppState>, key: &str) -> Option<String> {
    state
        .db
        .get_setting(key)
        .ok()
        .flatten()
        .filter(|s| !s.trim().is_empty())
}

fn google_client_id(state: &State<'_, AppState>) -> Option<String> {
    oauth_setting(state, "oauth.google.clientId")
}

fn google_client_secret(state: &State<'_, AppState>) -> Option<String> {
    oauth_setting(state, "oauth.google.clientSecret")
}

fn outlook_client_id(state: &State<'_, AppState>) -> Option<String> {
    oauth_setting(state, "oauth.outlook.clientId")
}

fn outlook_tenant(state: &State<'_, AppState>) -> String {
    oauth_setting(state, "oauth.outlook.tenant").unwrap_or_else(|| "common".to_string())
}

fn provider_label(provider: &str) -> &'static str {
    match provider {
        "google" => "Google",
        "outlook" => "Outlook",
        _ => "Calendar",
    }
}

fn provider_color(provider: &str) -> &'static str {
    match provider {
        "google" => "red",
        "outlook" => "blue",
        _ => "blue",
    }
}

fn build_auth_url(
    provider: &str,
    client_id: &str,
    redirect_uri: &str,
    state: &str,
    code_challenge: &str,
    tenant: &str,
) -> anyhow::Result<String> {
    let scope = match provider {
        "google" => "openid email profile https://www.googleapis.com/auth/calendar.readonly",
        "outlook" => "openid email profile offline_access Calendars.Read",
        other => anyhow::bail!("Unsupported OAuth provider: {other}"),
    };
    let auth_base = match provider {
        "google" => "https://accounts.google.com/o/oauth2/v2/auth".to_string(),
        "outlook" => format!(
            "https://login.microsoftonline.com/{}/oauth2/v2.0/authorize",
            url_encode(tenant)
        ),
        other => anyhow::bail!("Unsupported OAuth provider: {other}"),
    };
    Ok(format!(
        "{auth_base}?response_type=code&client_id={}&redirect_uri={}&scope={}&state={}&code_challenge={}&code_challenge_method=S256&access_type=offline&prompt=consent",
        url_encode(client_id),
        url_encode(redirect_uri),
        url_encode(scope),
        url_encode(state),
        url_encode(code_challenge),
    ))
}

async fn exchange_code_for_tokens(
    provider: &str,
    client_id: &str,
    client_secret: Option<&str>,
    redirect_uri: &str,
    code: &str,
    code_verifier: &str,
    tenant: &str,
) -> anyhow::Result<TokenResponse> {
    let client = Client::new();
    let token_url = match provider {
        "google" => "https://oauth2.googleapis.com/token".to_string(),
        "outlook" => format!(
            "https://login.microsoftonline.com/{}/oauth2/v2.0/token",
            tenant
        ),
        other => anyhow::bail!("Unsupported OAuth provider: {other}"),
    };

    let mut form: Vec<(&str, String)> = vec![
        ("grant_type", "authorization_code".into()),
        ("code", code.to_string()),
        ("redirect_uri", redirect_uri.to_string()),
        ("client_id", client_id.to_string()),
        ("code_verifier", code_verifier.to_string()),
    ];
    if let Some(secret) = client_secret.filter(|s| !s.trim().is_empty()) {
        form.push(("client_secret", secret.to_string()));
    }

    let resp = client.post(&token_url).form(&form).send().await?;
    let status = resp.status();
    let body: Value = resp.json().await?;
    if !status.is_success() {
        let msg = body
            .get("error_description")
            .or_else(|| body.get("error"))
            .and_then(|v| v.as_str())
            .unwrap_or("token exchange failed");
        anyhow::bail!("{msg}");
    }
    Ok(serde_json::from_value(body)?)
}

async fn refresh_access_token(
    provider: &str,
    client_id: &str,
    client_secret: Option<&str>,
    refresh_token: &str,
    tenant: &str,
) -> anyhow::Result<TokenResponse> {
    let client = Client::new();
    let token_url = match provider {
        "google" => "https://oauth2.googleapis.com/token".to_string(),
        "outlook" => format!(
            "https://login.microsoftonline.com/{}/oauth2/v2.0/token",
            tenant
        ),
        other => anyhow::bail!("Unsupported OAuth provider: {other}"),
    };
    let mut form: Vec<(&str, String)> = vec![
        ("grant_type", "refresh_token".into()),
        ("refresh_token", refresh_token.to_string()),
        ("client_id", client_id.to_string()),
    ];
    if let Some(secret) = client_secret.filter(|s| !s.trim().is_empty()) {
        form.push(("client_secret", secret.to_string()));
    }
    let resp = client.post(&token_url).form(&form).send().await?;
    let status = resp.status();
    let body: Value = resp.json().await?;
    if !status.is_success() {
        let msg = body
            .get("error_description")
            .or_else(|| body.get("error"))
            .and_then(|v| v.as_str())
            .unwrap_or("token refresh failed");
        anyhow::bail!("{msg}");
    }
    Ok(serde_json::from_value(body)?)
}

async fn fetch_account_email(provider: &str, access_token: &str) -> anyhow::Result<String> {
    let client = Client::new();
    match provider {
        "google" => {
            let resp = client
                .get("https://www.googleapis.com/oauth2/v2/userinfo")
                .bearer_auth(access_token)
                .send()
                .await?;
            let body: Value = resp.json().await?;
            Ok(body
                .get("email")
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .to_string())
        }
        "outlook" => {
            let resp = client
                .get("https://graph.microsoft.com/v1.0/me")
                .bearer_auth(access_token)
                .send()
                .await?;
            let body: Value = resp.json().await?;
            Ok(body
                .get("mail")
                .or_else(|| body.get("userPrincipalName"))
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .to_string())
        }
        other => anyhow::bail!("Unsupported OAuth provider: {other}"),
    }
}

fn token_needs_refresh(expires_at: Option<&str>) -> bool {
    let Some(raw) = expires_at else {
        return false;
    };
    if let Ok(dt) = chrono::DateTime::parse_from_rfc3339(raw) {
        return dt < Utc::now() + Duration::minutes(2);
    }
    false
}

async fn ensure_fresh_access_token_inner(
    state: &AppState,
    account_id: &str,
) -> anyhow::Result<String> {
    let (provider, access, refresh, expires_at) = load_oauth_tokens(state, account_id)?;

    if !token_needs_refresh(expires_at.as_deref()) {
        if access.trim().is_empty() {
            anyhow::bail!("OAuth session missing; reconnect {provider}");
        }
        return Ok(access);
    }
    if refresh.trim().is_empty() {
        anyhow::bail!("OAuth session expired; reconnect {provider}");
    }

    let client_id = match provider.as_str() {
        "google" => setting_value(state, "oauth.google.clientId")
            .filter(|s| !s.trim().is_empty())
            .ok_or_else(|| anyhow::anyhow!("Google client ID not configured"))?,
        "outlook" => setting_value(state, "oauth.outlook.clientId")
            .filter(|s| !s.trim().is_empty())
            .ok_or_else(|| anyhow::anyhow!("Outlook client ID not configured"))?,
        other => return Err(anyhow::anyhow!("Unsupported provider: {other}").into()),
    };
    let secret = match provider.as_str() {
        "google" => setting_value(state, "oauth.google.clientSecret"),
        _ => None,
    };
    let tenant = setting_value(state, "oauth.outlook.tenant").unwrap_or_else(|| "common".into());
    let tokens = refresh_access_token(
        &provider,
        &client_id,
        secret.as_deref(),
        &refresh,
        &tenant,
    )
    .await?;

    let now = Utc::now();
    let expires = tokens
        .expires_in
        .map(|secs| (now + Duration::seconds(secs)).to_rfc3339());
    let new_refresh = tokens
        .refresh_token
        .filter(|s| !s.is_empty())
        .unwrap_or(refresh);
    let access_token = tokens.access_token.clone();

    store_oauth_tokens(state, account_id, &access_token, &new_refresh)?;
    state.db.with_conn(|conn| {
        conn.execute(
            "UPDATE calendar_oauth_account
             SET access_token_enc = ?1, refresh_token_enc = ?2, expires_at = ?3, updated_at = ?4
             WHERE id = ?5",
            rusqlite::params![
                OAUTH_TOKEN_MARKER,
                OAUTH_TOKEN_MARKER,
                expires,
                now.to_rfc3339(),
                account_id
            ],
        )?;
        Ok(())
    })?;

    Ok(access_token)
}

fn setting_value(state: &AppState, key: &str) -> Option<String> {
    state
        .db
        .with_conn(|conn| {
            conn.query_row(
                "SELECT value FROM app_settings WHERE key = ?1 LIMIT 1",
                [key],
                |r| r.get(0),
            )
            .optional()
            .map_err(Into::into)
        })
        .ok()
        .flatten()
}

async fn ensure_fresh_access_token(
    state: &State<'_, AppState>,
    account_id: &str,
) -> anyhow::Result<String> {
    ensure_fresh_access_token_inner(state.inner(), account_id).await
}

fn upsert_oauth_account(
    conn: &Connection,
    provider: &str,
    email: &str,
    expires_at: Option<&str>,
    scopes: &str,
) -> rusqlite::Result<(String, String)> {
    ensure_default_calendar_source(conn)?;
    let now = Utc::now().to_rfc3339();
    let existing: Option<(String, Option<String>)> = conn
        .query_row(
            "SELECT id, source_id FROM calendar_oauth_account WHERE provider = ?1 LIMIT 1",
            [provider],
            |r| Ok((r.get(0)?, r.get(1)?)),
        )
        .ok();

    if let Some((account_id, source_id)) = existing {
        let source_id = if let Some(sid) = source_id.filter(|s| !s.is_empty()) {
            conn.execute(
                "UPDATE calendar_source SET name = ?1, provider = ?2 WHERE id = ?3",
                rusqlite::params![provider_label(provider), provider, sid],
            )
            .ok();
            sid
        } else {
            let sid = Uuid::new_v4().to_string();
            let sort: i64 = conn
                .query_row(
                    "SELECT COALESCE(MAX(sort_order), 0) + 1 FROM calendar_source",
                    [],
                    |r| r.get(0),
                )
                .unwrap_or(1);
            conn.execute(
                "INSERT INTO calendar_source (id, name, color, ics_url, is_enabled, sort_order, provider)
                 VALUES (?1, ?2, ?3, '', 1, ?4, ?5)",
                rusqlite::params![
                    sid,
                    provider_label(provider),
                    provider_color(provider),
                    sort,
                    provider
                ],
            )?;
            sid
        };

        conn.execute(
            "UPDATE calendar_oauth_account
             SET account_email = ?1, access_token_enc = ?2, refresh_token_enc = ?3,
                 expires_at = ?4, scopes = ?5, source_id = ?6, updated_at = ?7
             WHERE id = ?8",
            rusqlite::params![
                email,
                OAUTH_TOKEN_MARKER,
                OAUTH_TOKEN_MARKER,
                expires_at,
                scopes,
                source_id,
                now,
                account_id
            ],
        )?;
        Ok((account_id, source_id))
    } else {
        let account_id = Uuid::new_v4().to_string();
        let source_id = Uuid::new_v4().to_string();
        let sort: i64 = conn
            .query_row(
                "SELECT COALESCE(MAX(sort_order), 0) + 1 FROM calendar_source",
                [],
                |r| r.get(0),
            )
            .unwrap_or(1);
        conn.execute(
            "INSERT INTO calendar_source (id, name, color, ics_url, is_enabled, sort_order, provider)
             VALUES (?1, ?2, ?3, '', 1, ?4, ?5)",
            rusqlite::params![
                source_id,
                provider_label(provider),
                provider_color(provider),
                sort,
                provider
            ],
        )?;
        conn.execute(
            "INSERT INTO calendar_oauth_account
             (id, provider, account_email, access_token_enc, refresh_token_enc, expires_at, scopes, source_id, created_at, updated_at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10)",
            rusqlite::params![
                account_id,
                provider,
                email,
                OAUTH_TOKEN_MARKER,
                OAUTH_TOKEN_MARKER,
                expires_at,
                scopes,
                source_id,
                now,
                now
            ],
        )?;
        Ok((account_id, source_id))
    }
}

fn parse_api_datetime(value: &Value) -> Option<(String, bool)> {
    if let Some(dt) = value.get("dateTime").and_then(|v| v.as_str()) {
        return Some((dt.to_string(), false));
    }
    if let Some(d) = value.get("date").and_then(|v| v.as_str()) {
        return Some((format!("{d}T12:00:00Z"), true));
    }
    None
}

async fn sync_google_events(
    access_token: &str,
    time_min: &str,
    time_max: &str,
) -> anyhow::Result<Vec<(String, String, String, Option<String>, bool, String)>> {
    let client = Client::new();
    let url = format!(
        "https://www.googleapis.com/calendar/v3/calendars/primary/events?singleEvents=true&orderBy=startTime&timeMin={}&timeMax={}&maxResults=500",
        url_encode(time_min),
        url_encode(time_max),
    );
    let resp = client.get(&url).bearer_auth(access_token).send().await?;
    if !resp.status().is_success() {
        anyhow::bail!("Google Calendar API error: {}", resp.status());
    }
    let body: Value = resp.json().await?;
    let mut out = Vec::new();
    if let Some(items) = body.get("items").and_then(|v| v.as_array()) {
        for item in items {
            let id = item.get("id").and_then(|v| v.as_str()).unwrap_or("");
            if id.is_empty() {
                continue;
            }
            let title = item
                .get("summary")
                .and_then(|v| v.as_str())
                .unwrap_or("(No title)")
                .to_string();
            let start = item.get("start").and_then(parse_api_datetime);
            let end = item.get("end").and_then(parse_api_datetime);
            let (start_at, all_day) = start.unwrap_or_else(|| (Utc::now().to_rfc3339(), false));
            let end_at = end.map(|(v, _)| v);
            let location = item
                .get("location")
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .to_string();
            out.push((id.to_string(), title, start_at, end_at, all_day, location));
        }
    }
    Ok(out)
}

async fn sync_outlook_events(
    access_token: &str,
    time_min: &str,
    time_max: &str,
) -> anyhow::Result<Vec<(String, String, String, Option<String>, bool, String)>> {
    let client = Client::new();
    let url = format!(
        "https://graph.microsoft.com/v1.0/me/calendarview?startDateTime={}&endDateTime={}&$top=500&$orderby=start/dateTime",
        url_encode(time_min),
        url_encode(time_max),
    );
    let resp = client.get(&url).bearer_auth(access_token).send().await?;
    if !resp.status().is_success() {
        anyhow::bail!("Microsoft Graph error: {}", resp.status());
    }
    let body: Value = resp.json().await?;
    let mut out = Vec::new();
    if let Some(items) = body.get("value").and_then(|v| v.as_array()) {
        for item in items {
            let id = item.get("id").and_then(|v| v.as_str()).unwrap_or("");
            if id.is_empty() {
                continue;
            }
            let title = item
                .get("subject")
                .and_then(|v| v.as_str())
                .unwrap_or("(No title)")
                .to_string();
            let start = item.get("start").and_then(parse_api_datetime);
            let end = item.get("end").and_then(parse_api_datetime);
            let (start_at, all_day) = start.unwrap_or_else(|| (Utc::now().to_rfc3339(), false));
            let end_at = end.map(|(v, _)| v);
            let location = item
                .get("location")
                .and_then(|l| l.get("displayName"))
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .to_string();
            out.push((id.to_string(), title, start_at, end_at, all_day, location));
        }
    }
    Ok(out)
}

fn upsert_synced_events(
    conn: &Connection,
    source_id: &str,
    provider: &str,
    color: &str,
    events: &[(String, String, String, Option<String>, bool, String)],
) -> rusqlite::Result<(i64, i64)> {
    conn.execute(
        "DELETE FROM calendar_event WHERE source_id = ?1 AND provider = ?2",
        rusqlite::params![source_id, provider],
    )?;
    let now = Utc::now().to_rfc3339();
    let mut imported = 0i64;
    for (provider_event_id, title, start_at, end_at, all_day, location) in events {
        if title.trim().is_empty() || start_at.trim().is_empty() {
            continue;
        }
        conn.execute(
            "INSERT INTO calendar_event
             (id, title, start_at, end_at, all_day, location, notes, provider, provider_event_id,
              semester_id, course_id, color_hex, color, recurrence, source_id, created_at, updated_at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, '', ?7, ?8, NULL, NULL, NULL, ?9, 'none', ?10, ?11, ?11)",
            rusqlite::params![
                Uuid::new_v4().to_string(),
                title,
                start_at,
                end_at,
                i64::from(*all_day),
                location,
                provider,
                provider_event_id,
                color,
                source_id,
                now
            ],
        )?;
        imported += 1;
    }
    Ok((imported, 0))
}

fn resolve_account_for_sync(
    state: &State<'_, AppState>,
    provider: Option<String>,
    account_id: Option<String>,
) -> anyhow::Result<String> {
    state.db.with_conn(|conn| {
        if let Some(id) = account_id.filter(|s| !s.is_empty()) {
            let exists: bool = conn
                .query_row(
                    "SELECT EXISTS(SELECT 1 FROM calendar_oauth_account WHERE id = ?1)",
                    rusqlite::params![id],
                    |r| r.get(0),
                )
                .unwrap_or(false);
            if exists {
                return Ok(id);
            }
            anyhow::bail!("OAuth account not found");
        }
        if let Some(p) = provider.filter(|s| !s.is_empty()) {
            let id: Option<String> = conn
                .query_row(
                    "SELECT id FROM calendar_oauth_account WHERE provider = ?1 LIMIT 1",
                    rusqlite::params![p.to_lowercase()],
                    |r| r.get(0),
                )
                .optional()?;
            return id.ok_or_else(|| anyhow::anyhow!("No connected {p} account"));
        }
        anyhow::bail!("Provide provider or accountId")
    })
}

#[tauri::command]
pub fn calendar_oauth_begin(
    state: State<'_, AppState>,
    provider: String,
) -> CmdResult<CalendarOAuthBeginResult> {
    let provider = provider.to_lowercase();
    let client_id = match provider.as_str() {
        "google" => google_client_id(&state)
            .ok_or_else(|| anyhow::anyhow!("Add Google Client ID in Settings → Calendar OAuth"))?,
        "outlook" => outlook_client_id(&state)
            .ok_or_else(|| anyhow::anyhow!("Add Outlook Client ID in Settings → Calendar OAuth"))?,
        other => return Err(anyhow::anyhow!("Unsupported provider: {other}").into()),
    };

    let (listener, port) = pick_loopback_listener().map_err(anyhow::Error::from)?;
    let redirect_uri = format!("http://127.0.0.1:{port}{OAUTH_CALLBACK_PATH}");
    let state_token = Uuid::new_v4().to_string();
    let (code_verifier, code_challenge) = generate_pkce_pair();
    let tenant = outlook_tenant(&state);
    let auth_url = build_auth_url(
        &provider,
        &client_id,
        &redirect_uri,
        &state_token,
        &code_challenge,
        &tenant,
    )?;

    let (tx, rx) = mpsc::channel();
    spawn_callback_listener(listener, state_token.clone(), tx);
    OAuthSessions::global().inner.lock().insert(
        state_token.clone(),
        PendingOAuth {
            provider,
            code_verifier,
            redirect_uri: redirect_uri.clone(),
            code_rx: rx,
        },
    );

    Ok(CalendarOAuthBeginResult {
        auth_url,
        state: state_token,
        redirect_uri,
    })
}

#[tauri::command]
pub async fn calendar_oauth_complete(
    app: AppHandle,
    state: State<'_, AppState>,
    oauth_state: String,
) -> CmdResult<CalendarOAuthAccountDto> {
    let pending = OAuthSessions::global()
        .inner
        .lock()
        .remove(&oauth_state)
        .ok_or_else(|| anyhow::anyhow!("OAuth session expired; start connect again"))?;

    let code = tokio::task::spawn_blocking(move || {
        pending
            .code_rx
            .recv_timeout(StdDuration::from_secs(OAUTH_TIMEOUT_SECS))
    })
    .await
    .map_err(|e| anyhow::anyhow!("OAuth wait failed: {e}"))?
    .map_err(|_| anyhow::anyhow!("OAuth timed out after {OAUTH_TIMEOUT_SECS}s"))?
    .map_err(anyhow::Error::msg)?;

    let provider = pending.provider;
    let client_id = match provider.as_str() {
        "google" => google_client_id(&state)
            .ok_or_else(|| anyhow::anyhow!("Google client ID not configured"))?,
        "outlook" => outlook_client_id(&state)
            .ok_or_else(|| anyhow::anyhow!("Outlook client ID not configured"))?,
        other => return Err(anyhow::anyhow!("Unsupported provider: {other}").into()),
    };
    let secret = match provider.as_str() {
        "google" => google_client_secret(&state),
        _ => None,
    };
    let tenant = outlook_tenant(&state);

    let tokens = exchange_code_for_tokens(
        &provider,
        &client_id,
        secret.as_deref(),
        &pending.redirect_uri,
        &code,
        &pending.code_verifier,
        &tenant,
    )
    .await?;

    let email = fetch_account_email(&provider, &tokens.access_token).await?;
    let now = Utc::now();
    let expires_at = tokens
        .expires_in
        .map(|secs| (now + Duration::seconds(secs)).to_rfc3339());
    let scopes = tokens.scope.unwrap_or_default();
    let refresh = tokens.refresh_token.unwrap_or_default();

    let (account_id, _source_id) = state.db.with_conn(|conn| {
        upsert_oauth_account(
            conn,
            &provider,
            &email,
            expires_at.as_deref(),
            &scopes,
        )
        .map_err(Into::into)
    })?;
    store_oauth_tokens(state.inner(), &account_id, &tokens.access_token, &refresh)?;

    bump_calendar(&app, &state)?;

    let status = calendar_oauth_status(state)?;
    status
        .accounts
        .into_iter()
        .find(|a| a.id == account_id)
        .ok_or_else(|| anyhow::anyhow!("Connected account not found").into())
}

#[tauri::command]
pub fn calendar_oauth_status(state: State<'_, AppState>) -> CmdResult<CalendarOAuthStatus> {
    let google_configured = google_client_id(&state).is_some();
    let outlook_configured = outlook_client_id(&state).is_some();
    let accounts = state
        .db
        .with_conn(|conn| {
            let mut stmt = conn.prepare(
                "SELECT a.id, a.provider, a.account_email, a.source_id, a.scopes, a.expires_at,
                        s.last_synced_at
                 FROM calendar_oauth_account a
                 LEFT JOIN calendar_source s ON s.id = a.source_id
                 ORDER BY a.provider ASC",
            )?;
            let rows = stmt
                .query_map([], |r| {
                    Ok(CalendarOAuthAccountDto {
                        id: r.get(0)?,
                        provider: r.get(1)?,
                        account_email: r.get(2)?,
                        source_id: r.get(3)?,
                        scopes: r.get(4)?,
                        expires_at: r.get(5)?,
                        last_synced_at: r.get(6)?,
                    })
                })?
                .collect::<Result<Vec<_>, _>>()?;
            Ok(rows)
        })
        .map_err(anyhow::Error::from)?;

    Ok(CalendarOAuthStatus {
        accounts,
        google_configured,
        outlook_configured,
    })
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CalendarOAuthSyncAllResult {
    pub accounts: i64,
    pub imported: i64,
    pub skipped: i64,
    pub errors: Vec<String>,
}

async fn sync_oauth_account(
    app: &AppHandle,
    state: &AppState,
    account_id: &str,
) -> CmdResult<CalendarOAuthSyncResult> {
    let (provider_name, source_id, color) = state.db.with_conn(|conn| {
        conn.query_row(
            "SELECT a.provider, a.source_id, COALESCE(s.color, '')
             FROM calendar_oauth_account a
             LEFT JOIN calendar_source s ON s.id = a.source_id
             WHERE a.id = ?1",
            rusqlite::params![account_id],
            |r| {
                Ok((
                    r.get::<_, String>(0)?,
                    r.get::<_, Option<String>>(1)?,
                    r.get::<_, String>(2)?,
                ))
            },
        )
        .map_err(Into::into)
    })?;

    let source_id =
        source_id.ok_or_else(|| anyhow::anyhow!("OAuth account missing calendar source"))?;
    let access = ensure_fresh_access_token_inner(state, account_id).await?;

    let now = Utc::now();
    // Include a short lookback so recently started events aren't missed.
    let time_min = (now - Duration::days(7)).to_rfc3339();
    let time_max = (now + Duration::days(90)).to_rfc3339();

    let events = match provider_name.as_str() {
        "google" => sync_google_events(&access, &time_min, &time_max).await?,
        "outlook" => sync_outlook_events(&access, &time_min, &time_max).await?,
        other => return Err(anyhow::anyhow!("Unsupported provider: {other}").into()),
    };

    let synced_at = Utc::now().to_rfc3339();
    let color = if color.is_empty() {
        provider_color(&provider_name).to_string()
    } else {
        color
    };
    let (imported, skipped) = state.db.with_conn(|conn| {
        let (imported, skipped) =
            upsert_synced_events(conn, &source_id, &provider_name, &color, &events)?;
        conn.execute(
            "UPDATE calendar_source SET last_synced_at = ?1 WHERE id = ?2",
            rusqlite::params![synced_at, source_id],
        )?;
        Ok((imported, skipped))
    })?;

    bump_calendar(app, state)?;
    Ok(CalendarOAuthSyncResult {
        imported,
        skipped,
        last_synced_at: synced_at,
    })
}

#[tauri::command]
pub async fn calendar_oauth_sync_all(
    app: AppHandle,
    state: State<'_, AppState>,
) -> CmdResult<CalendarOAuthSyncAllResult> {
    let account_ids: Vec<(String, String)> = state.db.with_conn(|conn| {
        let mut stmt = conn.prepare(
            "SELECT id, provider FROM calendar_oauth_account ORDER BY provider ASC",
        )?;
        let rows = stmt
            .query_map([], |r| Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?)))?
            .collect::<Result<Vec<_>, _>>()?;
        Ok(rows)
    })?;

    let mut imported = 0i64;
    let mut skipped = 0i64;
    let mut errors = Vec::new();
    let mut accounts = 0i64;

    for (id, provider) in account_ids {
        match sync_oauth_account(&app, state.inner(), &id).await {
            Ok(res) => {
                accounts += 1;
                imported += res.imported;
                skipped += res.skipped;
            }
            Err(e) => errors.push(format!("{provider}: {}", e.message)),
        }
    }

    Ok(CalendarOAuthSyncAllResult {
        accounts,
        imported,
        skipped,
        errors,
    })
}

#[tauri::command]
pub async fn calendar_oauth_sync(
    app: AppHandle,
    state: State<'_, AppState>,
    provider: Option<String>,
    account_id: Option<String>,
) -> CmdResult<CalendarOAuthSyncResult> {
    let account_id = resolve_account_for_sync(&state, provider, account_id)?;
    sync_oauth_account(&app, state.inner(), &account_id).await
}

#[tauri::command]
pub fn calendar_oauth_disconnect(
    app: AppHandle,
    state: State<'_, AppState>,
    account_id: String,
) -> CmdResult<()> {
    clear_oauth_tokens(state.inner(), &account_id);
    let source_id: Option<String> = state.db.with_conn(|conn| {
        let source_id: Option<String> = conn
            .query_row(
                "SELECT source_id FROM calendar_oauth_account WHERE id = ?1",
                rusqlite::params![account_id],
                |r| r.get(0),
            )
            .optional()?
            .flatten();
        conn.execute(
            "DELETE FROM calendar_oauth_account WHERE id = ?1",
            rusqlite::params![account_id],
        )?;
        if let Some(ref sid) = source_id {
            conn.execute(
                "DELETE FROM calendar_event WHERE source_id = ?1",
                rusqlite::params![sid],
            )?;
            conn.execute(
                "DELETE FROM calendar_source WHERE id = ?1",
                rusqlite::params![sid],
            )?;
        }
        Ok(source_id)
    })?;

    let _ = source_id;
    bump_calendar(&app, &state)?;
    Ok(())
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CalendarOAuthPushResult {
    pub pushed: i64,
    pub skipped: i64,
    pub errors: Vec<String>,
}

/// Push College-local calendar events to Google/Outlook (EventKit two-way write substitute).
#[tauri::command]
pub async fn calendar_oauth_push_local(
    app: AppHandle,
    state: State<'_, AppState>,
    account_id: Option<String>,
    provider: Option<String>,
) -> CmdResult<CalendarOAuthPushResult> {
    let account_id = resolve_account_for_sync(&state, provider, account_id)?;
    let (provider_name, access) = {
        let access = ensure_fresh_access_token_inner(state.inner(), &account_id).await?;
        let (provider, _, _, _) = load_oauth_tokens(state.inner(), &account_id)?;
        (provider, access)
    };

    let lookback = (Utc::now() - Duration::days(7)).to_rfc3339();
    let lookahead = (Utc::now() + Duration::days(90)).to_rfc3339();

    let locals: Vec<(String, String, String, Option<String>, bool, String, String)> =
        state.db.with_conn(|conn| {
            let mut stmt = conn.prepare(
                "SELECT id, title, start_at, end_at, all_day, location, notes
                 FROM calendar_event
                 WHERE start_at >= ?1 AND start_at <= ?2
                   AND (provider_event_id IS NULL OR provider_event_id = '')
                   AND (provider IS NULL OR provider = '' OR provider = 'local' OR provider = 'college')
                 ORDER BY start_at ASC
                 LIMIT 200",
            )?;
            let rows = stmt
                .query_map(rusqlite::params![lookback, lookahead], |r| {
                    Ok((
                        r.get::<_, String>(0)?,
                        r.get::<_, String>(1)?,
                        r.get::<_, String>(2)?,
                        r.get::<_, Option<String>>(3)?,
                        r.get::<_, i64>(4)? != 0,
                        r.get::<_, String>(5)?,
                        r.get::<_, String>(6)?,
                    ))
                })?
                .collect::<Result<Vec<_>, _>>()?;
            Ok(rows)
        })?;

    let mut pushed = 0i64;
    let mut skipped = 0i64;
    let mut errors = Vec::new();

    for (id, title, start_at, end_at, all_day, location, notes) in locals {
        if title.trim().is_empty() {
            skipped += 1;
            continue;
        }
        let result = match provider_name.as_str() {
            "google" => {
                push_google_event(&access, &title, &start_at, end_at.as_deref(), all_day, &location, &notes)
                    .await
            }
            "outlook" => {
                push_outlook_event(&access, &title, &start_at, end_at.as_deref(), all_day, &location, &notes)
                    .await
            }
            other => Err(anyhow::anyhow!("Unsupported provider: {other}")),
        };
        match result {
            Ok(provider_event_id) => {
                let _ = state.db.with_conn(|conn| {
                    conn.execute(
                        "UPDATE calendar_event
                         SET provider = ?1, provider_event_id = ?2, updated_at = ?3
                         WHERE id = ?4",
                        rusqlite::params![
                            provider_name,
                            provider_event_id,
                            Utc::now().to_rfc3339(),
                            id
                        ],
                    )?;
                    Ok(())
                });
                pushed += 1;
            }
            Err(e) => {
                errors.push(format!("{title}: {e}"));
                skipped += 1;
            }
        }
    }

    bump_calendar(&app, &state)?;
    Ok(CalendarOAuthPushResult {
        pushed,
        skipped,
        errors,
    })
}

async fn push_google_event(
    access_token: &str,
    title: &str,
    start_at: &str,
    end_at: Option<&str>,
    all_day: bool,
    location: &str,
    notes: &str,
) -> anyhow::Result<String> {
    let client = Client::new();
    let end = end_at
        .filter(|s| !s.is_empty())
        .map(|s| s.to_string())
        .unwrap_or_else(|| start_at.to_string());
    let body = if all_day {
        let start_day = start_at.get(..10).unwrap_or(start_at);
        let end_day = end.get(..10).unwrap_or(&end);
        serde_json::json!({
            "summary": title,
            "description": notes,
            "location": location,
            "start": { "date": start_day },
            "end": { "date": end_day },
        })
    } else {
        serde_json::json!({
            "summary": title,
            "description": notes,
            "location": location,
            "start": { "dateTime": start_at },
            "end": { "dateTime": end },
        })
    };
    let resp = client
        .post("https://www.googleapis.com/calendar/v3/calendars/primary/events")
        .bearer_auth(access_token)
        .json(&body)
        .send()
        .await?;
    if !resp.status().is_success() {
        let status = resp.status();
        let text = resp.text().await.unwrap_or_default();
        anyhow::bail!("Google Calendar create {status}: {text}");
    }
    let json: Value = resp.json().await?;
    json.get("id")
        .and_then(|v| v.as_str())
        .map(|s| s.to_string())
        .ok_or_else(|| anyhow::anyhow!("Google create response missing id"))
}

async fn push_outlook_event(
    access_token: &str,
    title: &str,
    start_at: &str,
    end_at: Option<&str>,
    all_day: bool,
    location: &str,
    notes: &str,
) -> anyhow::Result<String> {
    let client = Client::new();
    let end = end_at
        .filter(|s| !s.is_empty())
        .map(|s| s.to_string())
        .unwrap_or_else(|| start_at.to_string());
    let body = serde_json::json!({
        "subject": title,
        "body": { "contentType": "Text", "content": notes },
        "location": { "displayName": location },
        "isAllDay": all_day,
        "start": { "dateTime": start_at.trim_end_matches('Z'), "timeZone": "UTC" },
        "end": { "dateTime": end.trim_end_matches('Z'), "timeZone": "UTC" },
    });
    let resp = client
        .post("https://graph.microsoft.com/v1.0/me/events")
        .bearer_auth(access_token)
        .json(&body)
        .send()
        .await?;
    if !resp.status().is_success() {
        let status = resp.status();
        let text = resp.text().await.unwrap_or_default();
        anyhow::bail!("Outlook create {status}: {text}");
    }
    let json: Value = resp.json().await?;
    json.get("id")
        .and_then(|v| v.as_str())
        .map(|s| s.to_string())
        .ok_or_else(|| anyhow::anyhow!("Outlook create response missing id"))
}
