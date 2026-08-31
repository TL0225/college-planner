//! Localhost / LAN HTTP server for a live webcal ICS subscription feed.

use crate::commands::calendar::build_ics_export;
use crate::commands::CmdResult;
use crate::AppState;
use parking_lot::Mutex;
use rusqlite::OptionalExtension;
use serde::{Deserialize, Serialize};
use std::io::{Read, Write};
use std::net::{TcpListener, TcpStream, UdpSocket};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::OnceLock;
use std::time::Duration as StdDuration;
use tauri::State;

const FEED_PATH: &str = "/feed.ics";
const BIND_MODE_SETTING: &str = "calendar.feed.bindMode";

static FEED_SERVER_PORT: OnceLock<u16> = OnceLock::new();
static FEED_BIND_LAN: AtomicBool = AtomicBool::new(false);
static ICS_CACHE: Mutex<String> = Mutex::new(String::new());

fn read_http_request_path(stream: &mut TcpStream) -> anyhow::Result<String> {
    stream.set_read_timeout(Some(StdDuration::from_secs(10)))?;
    let mut buf = [0u8; 4096];
    let n = stream.read(&mut buf)?;
    let req = String::from_utf8_lossy(&buf[..n]);
    let request_line = req.lines().next().unwrap_or("");
    let mut parts = request_line.split_whitespace();
    let _method = parts.next().unwrap_or("");
    let path = parts.next().unwrap_or("");
    let path_only = path.split('?').next().unwrap_or(path);
    Ok(path_only.to_string())
}

fn write_http_response(stream: &mut TcpStream, status: &str, content_type: &str, body: &[u8]) {
    let response = format!(
        "HTTP/1.1 {status}\r\nContent-Type: {content_type}\r\nContent-Length: {}\r\nConnection: close\r\n\r\n",
        body.len()
    );
    let _ = stream.write_all(response.as_bytes());
    let _ = stream.write_all(body);
    let _ = stream.flush();
}

fn handle_connection(mut stream: TcpStream) {
    let path = match read_http_request_path(&mut stream) {
        Ok(p) => p,
        Err(_) => {
            write_http_response(&mut stream, "400 Bad Request", "text/plain", b"Bad request");
            return;
        }
    };

    if path == FEED_PATH {
        let body = ICS_CACHE.lock().clone();
        write_http_response(
            &mut stream,
            "200 OK",
            "text/calendar; charset=utf-8",
            body.as_bytes(),
        );
    } else {
        write_http_response(&mut stream, "404 Not Found", "text/plain", b"Not found");
    }
}

fn spawn_feed_listener(listener: TcpListener) {
    std::thread::spawn(move || {
        for stream in listener.incoming().flatten() {
            std::thread::spawn(move || handle_connection(stream));
        }
    });
}

/// Best-effort primary IPv4 for LAN subscription URLs.
pub fn local_ipv4_address() -> Option<String> {
    let socket = UdpSocket::bind("0.0.0.0:0").ok()?;
    socket.connect("8.8.8.8:80").ok()?;
    match socket.local_addr().ok()?.ip() {
        std::net::IpAddr::V4(v4) if !v4.is_loopback() => Some(v4.to_string()),
        _ => None,
    }
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

fn bind_lan_enabled(state: &AppState) -> bool {
    settings_get(state, BIND_MODE_SETTING)
        .map(|v| v.eq_ignore_ascii_case("lan"))
        .unwrap_or(false)
}

/// Refresh the in-memory ICS cache from the database.
pub(crate) fn refresh_ics_cache(state: &AppState) -> CmdResult<()> {
    let (text, _) = build_ics_export(state)?;
    *ICS_CACHE.lock() = text;
    Ok(())
}

fn ensure_feed_server_started(state: &AppState) -> CmdResult<u16> {
    refresh_ics_cache(state)?;

    let want_lan = bind_lan_enabled(state);
    FEED_BIND_LAN.store(want_lan, Ordering::SeqCst);

    let port = *FEED_SERVER_PORT.get_or_init(|| {
        let bind_addr = if want_lan {
            "0.0.0.0:0"
        } else {
            "127.0.0.1:0"
        };
        let listener = TcpListener::bind(bind_addr).expect("bind calendar feed server");
        let port = listener.local_addr().expect("calendar feed local addr").port();
        spawn_feed_listener(listener);
        port
    });

    Ok(port)
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct WebcalUrlResult {
    pub url: String,
    pub http_url: String,
    pub port: u16,
    pub bind_mode: String,
    pub local_ip: Option<String>,
    pub lan_http_url: Option<String>,
    pub lan_webcal_url: Option<String>,
}

fn build_webcal_result(port: u16, bind_mode: &str, local_ip: Option<String>) -> WebcalUrlResult {
    let url = format!("webcal://127.0.0.1:{port}{FEED_PATH}");
    let http_url = format!("http://127.0.0.1:{port}{FEED_PATH}");
    let (lan_http_url, lan_webcal_url) = local_ip.as_ref().map(|ip| {
        (
            format!("http://{ip}:{port}{FEED_PATH}"),
            format!("webcal://{ip}:{port}{FEED_PATH}"),
        )
    }).unzip_or_option();

    WebcalUrlResult {
        url,
        http_url,
        port,
        bind_mode: bind_mode.to_string(),
        local_ip,
        lan_http_url,
        lan_webcal_url,
    }
}

trait UnzipOrOption {
    type Item;
    fn unzip_or_option(self) -> (Option<Self::Item>, Option<Self::Item>);
}

impl<T> UnzipOrOption for Option<(T, T)> {
    type Item = T;
    fn unzip_or_option(self) -> (Option<T>, Option<T>) {
        match self {
            Some((a, b)) => (Some(a), Some(b)),
            None => (None, None),
        }
    }
}

/// Start the feed server if needed and return subscription URLs.
#[tauri::command]
pub fn calendar_get_webcal_url(state: State<'_, AppState>) -> CmdResult<WebcalUrlResult> {
    let port = ensure_feed_server_started(&state)?;
    let bind_mode = if FEED_BIND_LAN.load(Ordering::SeqCst) {
        "lan"
    } else {
        "localhost"
    };
    let local_ip = if bind_mode == "lan" {
        local_ipv4_address()
    } else {
        None
    };
    Ok(build_webcal_result(port, bind_mode, local_ip))
}

/// Idempotent: bind the feed server once and refresh the ICS cache.
#[tauri::command]
pub fn calendar_start_feed_server(state: State<'_, AppState>) -> CmdResult<u16> {
    ensure_feed_server_started(&state)
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CalendarFeedBindInput {
    pub mode: String,
}

/// Set bind mode for the feed server (`localhost` or `lan`). Takes effect on next server start.
#[tauri::command]
pub fn calendar_set_feed_bind_mode(
    state: State<'_, AppState>,
    input: CalendarFeedBindInput,
) -> CmdResult<()> {
    let mode = input.mode.trim().to_lowercase();
    if mode != "localhost" && mode != "lan" {
        return Err(anyhow::anyhow!("bind mode must be 'localhost' or 'lan'").into());
    }
    settings_set(&state, BIND_MODE_SETTING, &mode)
}

#[tauri::command]
pub fn calendar_get_feed_bind_mode(state: State<'_, AppState>) -> CmdResult<String> {
    Ok(if bind_lan_enabled(&state) {
        "lan".into()
    } else {
        "localhost".into()
    })
}
