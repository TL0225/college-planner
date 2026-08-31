use crate::commands::CmdResult;
use crate::db::DbChangeEvent;
use crate::scrapers::fetch_text;
use crate::AppState;
use chrono::Utc;
use rusqlite::Connection;
use serde::{Deserialize, Serialize};
use tauri::{AppHandle, Emitter, State};
use uuid::Uuid;

pub const DEFAULT_CALENDAR_SOURCE_ID: &str = "cal-src-personal";

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CalendarEventDto {
    pub id: String,
    pub title: String,
    pub start_at: String,
    pub end_at: Option<String>,
    pub all_day: bool,
    pub location: String,
    pub notes: String,
    pub provider: String,
    pub color: String,
    pub recurrence: String,
    pub source_id: Option<String>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CalendarTaskDto {
    pub id: String,
    pub title: String,
    pub due_at: Option<String>,
    pub is_complete: bool,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CalendarSourceDto {
    pub id: String,
    pub name: String,
    pub color: String,
    pub ics_url: String,
    pub last_synced_at: Option<String>,
    pub is_enabled: bool,
    pub sort_order: i64,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UpsertCalendarSourceInput {
    pub id: Option<String>,
    pub name: String,
    pub color: Option<String>,
    pub ics_url: Option<String>,
    pub is_enabled: Option<bool>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ImportIcsInput {
    pub ics_text: String,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ImportIcsResult {
    pub imported: i64,
    pub skipped: i64,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SyncIcsResult {
    pub imported: i64,
    pub skipped: i64,
    pub last_synced_at: String,
}

pub(crate) fn ensure_default_calendar_source(conn: &Connection) -> rusqlite::Result<()> {
    conn.execute(
        "INSERT OR IGNORE INTO calendar_source (id, name, color, ics_url, is_enabled, sort_order)
         VALUES (?1, 'Personal', 'blue', '', 1, 0)",
        [DEFAULT_CALENDAR_SOURCE_ID],
    )?;
    Ok(())
}

pub(crate) fn bump_calendar(app: &AppHandle, state: &AppState) -> CmdResult<()> {
    let rev = state.db.bump_revision("calendar")?;
    let _ = app.emit(
        "db:change",
        DbChangeEvent {
            domain: "calendar".into(),
            revision: rev,
        },
    );
    Ok(())
}

#[tauri::command]
pub fn calendar_list_events(state: State<'_, AppState>) -> CmdResult<Vec<CalendarEventDto>> {
    state
        .db
        .with_conn(|conn| {
            ensure_default_calendar_source(conn)?;
            let mut stmt = conn.prepare(
                "SELECT id, title, start_at, end_at, all_day, location, notes, provider, color, recurrence, source_id
                 FROM calendar_event ORDER BY start_at ASC LIMIT 500",
            )?;
            let rows = stmt
                .query_map([], |r| {
                    Ok(CalendarEventDto {
                        id: r.get(0)?,
                        title: r.get(1)?,
                        start_at: r.get(2)?,
                        end_at: r.get(3)?,
                        all_day: r.get::<_, i64>(4)? != 0,
                        location: r.get(5)?,
                        notes: r.get(6)?,
                        provider: r.get(7)?,
                        color: r.get(8)?,
                        recurrence: r.get(9)?,
                        source_id: r.get(10)?,
                    })
                })?
                .collect::<Result<Vec<_>, _>>()?;
            Ok(rows)
        })
        .map_err(Into::into)
}

#[tauri::command]
pub fn calendar_list_tasks(state: State<'_, AppState>) -> CmdResult<Vec<CalendarTaskDto>> {
    state
        .db
        .with_conn(|conn| {
            let mut stmt = conn.prepare(
                "SELECT id, title, due_at, is_complete FROM planner_task
                 ORDER BY due_at IS NULL, due_at ASC LIMIT 200",
            )?;
            let rows = stmt
                .query_map([], |r| {
                    Ok(CalendarTaskDto {
                        id: r.get(0)?,
                        title: r.get(1)?,
                        due_at: r.get(2)?,
                        is_complete: r.get::<_, i64>(3)? != 0,
                    })
                })?
                .collect::<Result<Vec<_>, _>>()?;
            Ok(rows)
        })
        .map_err(Into::into)
}

#[tauri::command]
pub fn calendar_list_sources(state: State<'_, AppState>) -> CmdResult<Vec<CalendarSourceDto>> {
    state
        .db
        .with_conn(|conn| {
            ensure_default_calendar_source(conn)?;
            let mut stmt = conn.prepare(
                "SELECT id, name, color, ics_url, last_synced_at, is_enabled, sort_order
                 FROM calendar_source ORDER BY sort_order ASC, name ASC LIMIT 50",
            )?;
            let rows = stmt
                .query_map([], |r| {
                    Ok(CalendarSourceDto {
                        id: r.get(0)?,
                        name: r.get(1)?,
                        color: r.get(2)?,
                        ics_url: r.get(3)?,
                        last_synced_at: r.get(4)?,
                        is_enabled: r.get::<_, i64>(5)? != 0,
                        sort_order: r.get(6)?,
                    })
                })?
                .collect::<Result<Vec<_>, _>>()?;
            Ok(rows)
        })
        .map_err(Into::into)
}

#[tauri::command]
pub fn calendar_upsert_source(
    app: AppHandle,
    state: State<'_, AppState>,
    input: UpsertCalendarSourceInput,
) -> CmdResult<String> {
    let color = input.color.unwrap_or_default();
    let ics_url = input.ics_url.unwrap_or_default();
    let is_enabled = i64::from(input.is_enabled.unwrap_or(true));
    let id = if let Some(existing) = input.id.filter(|s| !s.is_empty()) {
        state.db.with_conn(|conn| {
            conn.execute(
                "UPDATE calendar_source
                 SET name = ?1, color = ?2, ics_url = ?3, is_enabled = ?4
                 WHERE id = ?5",
                rusqlite::params![input.name, color, ics_url, is_enabled, existing],
            )?;
            Ok(())
        })?;
        existing
    } else {
        let id = Uuid::new_v4().to_string();
        state.db.with_conn(|conn| {
            ensure_default_calendar_source(conn)?;
            let sort: i64 = conn
                .query_row(
                    "SELECT COALESCE(MAX(sort_order), 0) + 1 FROM calendar_source",
                    [],
                    |r| r.get(0),
                )
                .unwrap_or(1);
            conn.execute(
                "INSERT INTO calendar_source (id, name, color, ics_url, is_enabled, sort_order)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
                rusqlite::params![id, input.name, color, ics_url, is_enabled, sort],
            )?;
            Ok(())
        })?;
        id
    };
    bump_calendar(&app, &state)?;
    Ok(id)
}

#[tauri::command]
pub fn calendar_delete_source(
    app: AppHandle,
    state: State<'_, AppState>,
    id: String,
) -> CmdResult<()> {
    if id == DEFAULT_CALENDAR_SOURCE_ID {
        return Err(anyhow::anyhow!("Cannot delete the default Personal calendar").into());
    }
    state.db.with_conn(|conn| {
        conn.execute(
            "DELETE FROM calendar_event WHERE source_id = ?1",
            rusqlite::params![id],
        )?;
        conn.execute(
            "DELETE FROM calendar_source WHERE id = ?1",
            rusqlite::params![id],
        )?;
        Ok(())
    })?;
    bump_calendar(&app, &state)?;
    Ok(())
}

fn ics_unescape(value: &str) -> String {
    value
        .replace("\\n", "\n")
        .replace("\\,", ",")
        .replace("\\;", ";")
        .replace("\\\\", "\\")
}

fn parse_ics_datetime(raw: &str) -> String {
    let s = raw.trim();
    let date_part = s.split(':').next_back().unwrap_or(s);
    if date_part.len() >= 8 && date_part.as_bytes().iter().take(8).all(|b| b.is_ascii_digit()) {
        let y = &date_part[0..4];
        let m = &date_part[4..6];
        let d = &date_part[6..8];
        if date_part.len() >= 15 && date_part.as_bytes()[8] == b'T' {
            let hh = &date_part[9..11];
            let mm = &date_part[11..13];
            let ss = &date_part[13..15];
            if date_part.ends_with('Z') {
                return format!("{y}-{m}-{d}T{hh}:{mm}:{ss}Z");
            }
            return format!("{y}-{m}-{d}T{hh}:{mm}:{ss}");
        }
        return format!("{y}-{m}-{d}T12:00:00Z");
    }
    Utc::now().to_rfc3339()
}

pub(crate) fn import_ics_into_conn(
    conn: &Connection,
    ics_text: &str,
    source_id: Option<&str>,
    provider: &str,
    default_color: &str,
) -> rusqlite::Result<(i64, i64)> {
    let mut imported = 0i64;
    let mut skipped = 0i64;
    let now = Utc::now().to_rfc3339();
    let unfolded = ics_text
        .replace("\r\n ", "")
        .replace("\n ", "")
        .replace("\r\n", "\n");

    let mut in_event = false;
    let mut summary = String::new();
    let mut dtstart = String::new();
    let mut location = String::new();
    let mut description = String::new();

    for line in unfolded.lines() {
        let upper = line.to_ascii_uppercase();
        if upper.starts_with("BEGIN:VEVENT") {
            in_event = true;
            summary.clear();
            dtstart.clear();
            location.clear();
            description.clear();
            continue;
        }
        if upper.starts_with("END:VEVENT") {
            if in_event {
                if summary.trim().is_empty() || dtstart.trim().is_empty() {
                    skipped += 1;
                } else {
                    let id = Uuid::new_v4().to_string();
                    let start = parse_ics_datetime(&dtstart);
                    conn.execute(
                        "INSERT INTO calendar_event
                         (id, title, start_at, end_at, all_day, location, notes, provider, provider_event_id,
                          semester_id, course_id, color_hex, color, recurrence, source_id, created_at, updated_at)
                         VALUES (?1, ?2, ?3, NULL, 0, ?4, ?5, ?6, NULL, NULL, NULL, NULL, ?7, 'none', ?8, ?9, ?9)",
                        rusqlite::params![
                            id,
                            summary.trim(),
                            start,
                            location.trim(),
                            description.trim(),
                            provider,
                            default_color,
                            source_id,
                            now
                        ],
                    )?;
                    imported += 1;
                }
            }
            in_event = false;
            continue;
        }
        if !in_event {
            continue;
        }
        if let Some(rest) = line.strip_prefix("SUMMARY:") {
            summary = ics_unescape(rest);
        } else if let Some(rest) = line.strip_prefix("SUMMARY;") {
            summary = ics_unescape(rest.split_once(':').map(|(_, v)| v).unwrap_or(rest));
        } else if let Some(rest) = line.strip_prefix("DTSTART:") {
            dtstart = rest.to_string();
        } else if let Some(rest) = line.strip_prefix("DTSTART;") {
            dtstart = rest.split_once(':').map(|(_, v)| v).unwrap_or(rest).to_string();
        } else if let Some(rest) = line.strip_prefix("LOCATION:") {
            location = ics_unescape(rest);
        } else if let Some(rest) = line.strip_prefix("LOCATION;") {
            location = ics_unescape(rest.split_once(':').map(|(_, v)| v).unwrap_or(rest));
        } else if let Some(rest) = line.strip_prefix("DESCRIPTION:") {
            description = ics_unescape(rest);
        } else if let Some(rest) = line.strip_prefix("DESCRIPTION;") {
            description = ics_unescape(rest.split_once(':').map(|(_, v)| v).unwrap_or(rest));
        }
    }
    Ok((imported, skipped))
}

fn import_ics_text(
    app: &AppHandle,
    state: &State<'_, AppState>,
    ics_text: &str,
) -> CmdResult<ImportIcsResult> {
    let (imported, skipped) = state.db.with_conn(|conn| {
        ensure_default_calendar_source(conn)?;
        Ok(import_ics_into_conn(conn, ics_text, None, "ics", "")?)
    })?;
    bump_calendar(app, state)?;
    Ok(ImportIcsResult { imported, skipped })
}

/// Minimal VEVENT importer (SUMMARY + DTSTART + optional LOCATION/DESCRIPTION).
#[tauri::command]
pub fn calendar_import_ics(
    app: AppHandle,
    state: State<'_, AppState>,
    input: ImportIcsInput,
) -> CmdResult<ImportIcsResult> {
    import_ics_text(&app, &state, &input.ics_text)
}

#[tauri::command]
pub fn calendar_import_ics_path(
    app: AppHandle,
    state: State<'_, AppState>,
    path: String,
) -> CmdResult<ImportIcsResult> {
    let ics_text = std::fs::read_to_string(&path).map_err(anyhow::Error::from)?;
    import_ics_text(&app, &state, &ics_text)
}

#[tauri::command]
pub async fn calendar_sync_ics_url(
    app: AppHandle,
    state: State<'_, AppState>,
    source_id: String,
) -> CmdResult<SyncIcsResult> {
    let (ics_url, color) = state
        .db
        .with_conn(|conn| {
            conn.query_row(
                "SELECT ics_url, color FROM calendar_source WHERE id = ?1",
                rusqlite::params![source_id],
                |r| Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?)),
            )
            .map_err(|_| anyhow::anyhow!("Calendar source not found"))
        })?;

    if ics_url.trim().is_empty() {
        return Err(anyhow::anyhow!("This calendar has no ICS subscription URL").into());
    }

    let fetch_url = ics_url
        .trim()
        .replacen("webcal://", "https://", 1)
        .replacen("webcals://", "https://", 1);

    let ics_text = fetch_text(&fetch_url).await?;

    let now = Utc::now().to_rfc3339();
    let (imported, skipped) = state.db.with_conn(|conn| {
        conn.execute(
            "DELETE FROM calendar_event WHERE source_id = ?1 AND provider = 'ics_sync'",
            rusqlite::params![source_id],
        )?;
        let (imported, skipped) = import_ics_into_conn(
            conn,
            &ics_text,
            Some(&source_id),
            "ics_sync",
            &color,
        )?;
        conn.execute(
            "UPDATE calendar_source SET last_synced_at = ?1 WHERE id = ?2",
            rusqlite::params![now, source_id],
        )?;
        Ok((imported, skipped))
    })?;

    bump_calendar(&app, &state)?;
    Ok(SyncIcsResult {
        imported,
        skipped,
        last_synced_at: now,
    })
}

fn ics_escape(value: &str) -> String {
    value
        .replace('\\', "\\\\")
        .replace(';', "\\;")
        .replace(',', "\\,")
        .replace('\n', "\\n")
}

fn to_ics_utc(iso: &str) -> String {
    // Accept RFC3339-ish and emit YYYYMMDDTHHMMSSZ when possible.
    let cleaned = iso.trim().replace(['-', ':'], "");
    if let Some(t_idx) = cleaned.find('T') {
        let date = &cleaned[..t_idx.min(8)];
        let rest = &cleaned[t_idx + 1..];
        let time: String = rest.chars().filter(|c| c.is_ascii_digit()).take(6).collect();
        let time = if time.len() >= 6 {
            time[..6].to_string()
        } else {
            format!("{:0<6}", time)
        };
        return format!("{date}T{time}Z");
    }
    if cleaned.len() >= 8 {
        return format!("{}T120000Z", &cleaned[..8]);
    }
    Utc::now().format("%Y%m%dT%H%M%SZ").to_string()
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ExportIcsPathResult {
    pub event_count: i64,
    pub path: String,
}

pub(crate) fn build_ics_export(state: &AppState) -> CmdResult<(String, i64)> {
    let events: Vec<(String, String, String, String)> = state.db.with_conn(|conn| {
        let mut stmt = conn.prepare(
            "SELECT id, title, start_at, location FROM calendar_event
             ORDER BY start_at ASC LIMIT 500",
        )?;
        let rows = stmt
            .query_map([], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?)))?
            .collect::<Result<Vec<_>, _>>()?;
        Ok(rows)
    })?;

    let count = events.len() as i64;
    let mut out = String::from(
        "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//College//Desktop//EN\r\nCALSCALE:GREGORIAN\r\n",
    );
    let stamp = Utc::now().format("%Y%m%dT%H%M%SZ");
    for (id, title, start_at, location) in events {
        out.push_str("BEGIN:VEVENT\r\n");
        out.push_str(&format!("UID:{id}@college.desktop\r\n"));
        out.push_str(&format!("DTSTAMP:{stamp}\r\n"));
        out.push_str(&format!("DTSTART:{}\r\n", to_ics_utc(&start_at)));
        out.push_str(&format!("SUMMARY:{}\r\n", ics_escape(&title)));
        if !location.trim().is_empty() {
            out.push_str(&format!("LOCATION:{}\r\n", ics_escape(&location)));
        }
        out.push_str("END:VEVENT\r\n");
    }
    out.push_str("END:VCALENDAR\r\n");
    Ok((out, count))
}

#[tauri::command]
pub fn calendar_export_ics(state: State<'_, AppState>) -> CmdResult<String> {
    Ok(build_ics_export(&state)?.0)
}

#[tauri::command]
pub fn calendar_export_ics_path(
    state: State<'_, AppState>,
    path: String,
) -> CmdResult<ExportIcsPathResult> {
    let (text, event_count) = build_ics_export(&state)?;
    if let Some(parent) = std::path::Path::new(&path).parent() {
        std::fs::create_dir_all(parent).map_err(anyhow::Error::from)?;
    }
    std::fs::write(&path, text).map_err(anyhow::Error::from)?;
    Ok(ExportIcsPathResult { event_count, path })
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SubscribeFeedResult {
    pub path: String,
    pub event_count: i64,
    pub written_at: String,
}

/// Write a stable ICS feed file for Apple Calendar / other subscribers (EventKit substitute).
pub(crate) fn publish_subscribe_feed_inner(state: &AppState) -> CmdResult<SubscribeFeedResult> {
    let (text, event_count) = build_ics_export(state)?;
    let feed_dir = state.paths.root.join("Calendar");
    std::fs::create_dir_all(&feed_dir).map_err(anyhow::Error::from)?;
    let path = feed_dir.join("college-subscribe.ics");
    std::fs::write(&path, text).map_err(anyhow::Error::from)?;
    Ok(SubscribeFeedResult {
        path: path.display().to_string(),
        event_count,
        written_at: Utc::now().to_rfc3339(),
    })
}

#[tauri::command]
pub fn calendar_publish_subscribe_feed(state: State<'_, AppState>) -> CmdResult<SubscribeFeedResult> {
    let result = publish_subscribe_feed_inner(&state)?;
    let _ = super::calendar_feed_server::refresh_ics_cache(&state);
    Ok(result)
}

/// macOS: publish feed then open Calendar.app with the ICS file for subscribe/import.
#[tauri::command]
pub fn calendar_open_apple_calendar_feed(state: State<'_, AppState>) -> CmdResult<SubscribeFeedResult> {
    #[cfg(not(target_os = "macos"))]
    {
        return Err(anyhow::anyhow!(
            "Apple Calendar handoff is macOS-only; use the published ICS path on other platforms"
        )
        .into());
    }
    #[cfg(target_os = "macos")]
    {
        let result = publish_subscribe_feed_inner(&state)?;
        std::process::Command::new("open")
            .args(["-a", "Calendar", result.path.as_str()])
            .spawn()
            .map_err(anyhow::Error::from)?;
        Ok(result)
    }
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct GeocodeLocationResult {
    pub lat: f64,
    pub lon: f64,
    pub display_name: String,
}

#[derive(Debug, Deserialize)]
struct NominatimHit {
    lat: String,
    lon: String,
    display_name: String,
}

/// Forward-geocode a free-text location via OpenStreetMap Nominatim (MapKit substitute).
#[tauri::command]
pub async fn calendar_geocode_location(query: String) -> CmdResult<GeocodeLocationResult> {
    let trimmed = query.trim();
    if trimmed.is_empty() {
        return Err(anyhow::anyhow!("Location query is empty").into());
    }

    let url = reqwest::Url::parse_with_params(
        "https://nominatim.openstreetmap.org/search",
        &[("q", trimmed), ("format", "json"), ("limit", "1")],
    )
    .map_err(anyhow::Error::from)?;

    let client = reqwest::Client::builder()
        .user_agent("CollegeDesktop/0.1 (+https://college.app)")
        .timeout(std::time::Duration::from_secs(15))
        .build()
        .map_err(anyhow::Error::from)?;

    let response = client
        .get(url)
        .header("Accept", "application/json")
        .send()
        .await
        .map_err(anyhow::Error::from)?;

    if !response.status().is_success() {
        return Err(anyhow::anyhow!("Nominatim returned HTTP {}", response.status()).into());
    }

    let hits: Vec<NominatimHit> = response.json().await.map_err(anyhow::Error::from)?;
    let hit = hits
        .into_iter()
        .next()
        .ok_or_else(|| anyhow::anyhow!("No results for \"{trimmed}\""))?;

    let lat: f64 = hit
        .lat
        .parse()
        .map_err(|_| anyhow::anyhow!("Invalid latitude from Nominatim"))?;
    let lon: f64 = hit
        .lon
        .parse()
        .map_err(|_| anyhow::anyhow!("Invalid longitude from Nominatim"))?;

    Ok(GeocodeLocationResult {
        lat,
        lon,
        display_name: hit.display_name,
    })
}

/// Search locations — returns up to 6 Nominatim matches for autocomplete.
#[tauri::command]
pub async fn calendar_search_locations(query: String) -> CmdResult<Vec<GeocodeLocationResult>> {
    let trimmed = query.trim();
    if trimmed.len() < 2 {
        return Ok(vec![]);
    }

    let url = reqwest::Url::parse_with_params(
        "https://nominatim.openstreetmap.org/search",
        &[("q", trimmed), ("format", "json"), ("limit", "6"), ("addressdetails", "0")],
    )
    .map_err(anyhow::Error::from)?;

    let client = reqwest::Client::builder()
        .user_agent("CollegeDesktop/0.1 (+https://college.app)")
        .timeout(std::time::Duration::from_secs(12))
        .build()
        .map_err(anyhow::Error::from)?;

    let response = client
        .get(url)
        .header("Accept", "application/json")
        .send()
        .await
        .map_err(anyhow::Error::from)?;

    if !response.status().is_success() {
        return Err(anyhow::anyhow!("Nominatim returned HTTP {}", response.status()).into());
    }

    let hits: Vec<NominatimHit> = response.json().await.map_err(anyhow::Error::from)?;
    let mut out = Vec::with_capacity(hits.len());
    for hit in hits {
        let lat: f64 = hit
            .lat
            .parse()
            .map_err(|_| anyhow::anyhow!("Invalid latitude from Nominatim"))?;
        let lon: f64 = hit
            .lon
            .parse()
            .map_err(|_| anyhow::anyhow!("Invalid longitude from Nominatim"))?;
        out.push(GeocodeLocationResult {
            lat,
            lon,
            display_name: hit.display_name,
        });
    }
    Ok(out)
}
