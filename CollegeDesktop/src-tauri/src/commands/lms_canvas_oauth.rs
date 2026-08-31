//! Canvas LMS OAuth2 (institution developer key + loopback redirect).

use crate::commands::lms::LmsCanvasConfigDto;
use crate::commands::CmdResult;
use crate::AppState;
use parking_lot::Mutex;
use rusqlite::OptionalExtension;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::io::{Read, Write};
use std::net::{TcpListener, TcpStream};
use std::sync::{OnceLock};
use std::time::Duration as StdDuration;
use tauri::State;
use uuid::Uuid;

const CANVAS_CALLBACK_PATH: &str = "/canvas/oauth/callback";
const CANVAS_SECRET_NS: &str = "lms";
const CANVAS_SECRET_KEY: &str = "canvas";

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CanvasSecretConfig {
    pub base_url: String,
    pub access_token: String,
    #[serde(default)]
    pub refresh_token: Option<String>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LmsCanvasOAuthBeginResult {
    pub auth_url: String,
    pub state: String,
    pub redirect_uri: String,
}

struct PendingCanvasOAuth {
    base_url: String,
    client_id: String,
    client_secret: String,
    redirect_uri: String,
    code_rx: std::sync::mpsc::Receiver<Result<String, String>>,
}

struct CanvasOAuthSessions {
    inner: Mutex<HashMap<String, PendingCanvasOAuth>>,
}

impl CanvasOAuthSessions {
    fn global() -> &'static CanvasOAuthSessions {
        static SESSIONS: OnceLock<CanvasOAuthSessions> = OnceLock::new();
        SESSIONS.get_or_init(|| CanvasOAuthSessions {
            inner: Mutex::new(HashMap::new()),
        })
    }
}

pub fn normalize_canvas_base_url(raw: &str) -> String {
    let trimmed = raw.trim().trim_end_matches('/');
    if trimmed.is_empty() {
        return String::new();
    }
    if trimmed.starts_with("http://") || trimmed.starts_with("https://") {
        trimmed.to_string()
    } else {
        format!("https://{trimmed}")
    }
}

fn load_canvas_secret(state: &AppState) -> CmdResult<Option<CanvasSecretConfig>> {
    let raw = state
        .security
        .get_secret(CANVAS_SECRET_NS, CANVAS_SECRET_KEY)?
        .and_then(|b| String::from_utf8(b).ok());
    Ok(raw.and_then(|text| serde_json::from_str(&text).ok()))
}

fn save_canvas_secret(state: &AppState, config: &CanvasSecretConfig) -> CmdResult<()> {
    let json = serde_json::to_string(config).map_err(|e| anyhow::anyhow!(e))?;
    state
        .security
        .set_secret(CANVAS_SECRET_NS, CANVAS_SECRET_KEY, json.as_bytes())?;
    Ok(())
}

fn settings_get(state: &AppState, key: &str) -> Option<String> {
    state
        .db
        .with_conn(|conn| {
            conn.query_row(
                "SELECT value FROM app_settings WHERE key = ?1",
                rusqlite::params![key],
                |r| r.get(0),
            )
            .optional()
            .map_err(Into::into)
        })
        .ok()
        .flatten()
}

fn settings_set(state: &AppState, key: &str, value: &str) -> CmdResult<()> {
    state.db.with_conn(|conn| {
        conn.execute(
            "INSERT INTO app_settings (key, value) VALUES (?1, ?2)
             ON CONFLICT(key) DO UPDATE SET value = excluded.value",
            rusqlite::params![key, value],
        )?;
        Ok(())
    })?;
    Ok(())
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
        "<html><body><h2>College</h2><p>Canvas connected. You can close this tab.</p></body></html>"
    } else {
        "<html><body><h2>College</h2><p>Canvas connection failed. Return to the app and try again.</p></body></html>"
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

fn spawn_canvas_callback_listener(
    listener: TcpListener,
    state_token: String,
    result_tx: std::sync::mpsc::Sender<Result<String, String>>,
) {
    std::thread::spawn(move || {
        if let Ok((mut stream, _)) = listener.accept() {
            let result = (|| -> Result<String, String> {
                let (path, query) = read_http_request(&mut stream).map_err(|e| e.to_string())?;
                if path != CANVAS_CALLBACK_PATH {
                    return Err("Unexpected callback path".into());
                }
                let returned_state = parse_query_param(&query, "state").ok_or("Missing state")?;
                if returned_state != state_token {
                    return Err("State mismatch".into());
                }
                if let Some(err) = parse_query_param(&query, "error") {
                    return Err(format!("Canvas OAuth error: {err}"));
                }
                let code = parse_query_param(&query, "code").ok_or("Missing authorization code")?;
                Ok(code)
            })();
            let success = result.is_ok();
            let _ = write_oauth_response(&mut stream, success);
            let _ = result_tx.send(result);
        }
    });
}

#[derive(Debug, Deserialize)]
struct CanvasTokenResponse {
    access_token: Option<String>,
    refresh_token: Option<String>,
    token_type: Option<String>,
}

async fn exchange_canvas_code(
    base_url: &str,
    client_id: &str,
    client_secret: &str,
    redirect_uri: &str,
    code: &str,
) -> anyhow::Result<CanvasSecretConfig> {
    let token_url = format!("{}/login/oauth2/token", base_url.trim_end_matches('/'));
    let client = reqwest::Client::new();
    let resp = client
        .post(&token_url)
        .form(&[
            ("grant_type", "authorization_code"),
            ("client_id", client_id),
            ("client_secret", client_secret),
            ("redirect_uri", redirect_uri),
            ("code", code),
        ])
        .send()
        .await?;
    if !resp.status().is_success() {
        let body = resp.text().await.unwrap_or_default();
        anyhow::bail!("Canvas token exchange HTTP error: {body}");
    }
    let parsed: CanvasTokenResponse = resp.json().await?;
    let access_token = parsed
        .access_token
        .filter(|t| !t.is_empty())
        .ok_or_else(|| anyhow::anyhow!("Canvas token response missing access_token"))?;
    Ok(CanvasSecretConfig {
        base_url: base_url.to_string(),
        access_token,
        refresh_token: parsed.refresh_token,
    })
}

#[tauri::command]
pub fn lms_canvas_oauth_begin(
    state: State<'_, AppState>,
    base_url: String,
) -> CmdResult<LmsCanvasOAuthBeginResult> {
    let base_url = normalize_canvas_base_url(&base_url);
    if base_url.is_empty() {
        return Err(anyhow::anyhow!("Canvas base URL required").into());
    }
    let client_id = settings_get(state.inner(), "lms.canvas.clientId")
        .filter(|s| !s.trim().is_empty())
        .ok_or_else(|| anyhow::anyhow!("Add Canvas Client ID in Settings → LMS"))?;
    let client_secret = settings_get(state.inner(), "lms.canvas.clientSecret")
        .filter(|s| !s.trim().is_empty())
        .ok_or_else(|| anyhow::anyhow!("Add Canvas Client Secret in Settings → LMS"))?;

    let (listener, port) = pick_loopback_listener().map_err(anyhow::Error::from)?;
    let redirect_uri = format!("http://127.0.0.1:{port}{CANVAS_CALLBACK_PATH}");
    let state_token = Uuid::new_v4().to_string();

    let auth_url = format!(
        "{}/login/oauth2/auth?client_id={}&response_type=code&redirect_uri={}&state={}",
        base_url.trim_end_matches('/'),
        urlencoding::encode(&client_id),
        urlencoding::encode(&redirect_uri),
        urlencoding::encode(&state_token),
    );

    let (tx, rx) = std::sync::mpsc::channel();
    spawn_canvas_callback_listener(listener, state_token.clone(), tx);
    CanvasOAuthSessions::global().inner.lock().insert(
        state_token.clone(),
        PendingCanvasOAuth {
            base_url,
            client_id,
            client_secret,
            redirect_uri: redirect_uri.clone(),
            code_rx: rx,
        },
    );

    Ok(LmsCanvasOAuthBeginResult {
        auth_url,
        state: state_token,
        redirect_uri,
    })
}

#[tauri::command]
pub async fn lms_canvas_oauth_complete(
    state: State<'_, AppState>,
    oauth_state: String,
) -> CmdResult<LmsCanvasConfigDto> {
    let pending = CanvasOAuthSessions::global()
        .inner
        .lock()
        .remove(&oauth_state)
        .ok_or_else(|| anyhow::anyhow!("Canvas OAuth session expired — start again"))?;

    let code = tokio::task::spawn_blocking(move || pending.code_rx.recv())
        .await
        .map_err(|e| anyhow::anyhow!(e))?
        .map_err(|_| anyhow::anyhow!("Canvas OAuth callback channel closed"))?
        .map_err(|e| anyhow::anyhow!(e))?;

    let config = exchange_canvas_code(
        &pending.base_url,
        &pending.client_id,
        &pending.client_secret,
        &pending.redirect_uri,
        &code,
    )
    .await?;

    save_canvas_secret(state.inner(), &config)?;

    Ok(LmsCanvasConfigDto {
        base_url: config.base_url,
        connected: true,
        auth_method: Some("oauth".into()),
    })
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LmsCanvasOAuthCredentialsInput {
    pub client_id: String,
    pub client_secret: String,
}

#[tauri::command]
pub fn lms_canvas_oauth_set_credentials(
    state: State<'_, AppState>,
    input: LmsCanvasOAuthCredentialsInput,
) -> CmdResult<()> {
    let client_id = input.client_id.trim();
    let client_secret = input.client_secret.trim();
    if client_id.is_empty() {
        return Err(anyhow::anyhow!("Canvas Client ID required").into());
    }
    settings_set(state.inner(), "lms.canvas.clientId", client_id)?;
    if !client_secret.is_empty() {
        settings_set(state.inner(), "lms.canvas.clientSecret", client_secret)?;
    }
    Ok(())
}

pub(crate) fn load_canvas_config(state: &AppState) -> CmdResult<Option<CanvasSecretConfig>> {
    load_canvas_secret(state)
}

pub(crate) fn save_canvas_config(state: &AppState, config: &CanvasSecretConfig) -> CmdResult<()> {
    save_canvas_secret(state, config)
}
