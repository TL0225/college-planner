use crate::commands::CmdResult;
use crate::db::DbChangeEvent;
use crate::AppState;
use chrono::Utc;
use serde::{Deserialize, Serialize};
use tauri::{AppHandle, Emitter, State};
use uuid::Uuid;

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LmsPortalDto {
    pub id: String,
    pub name: String,
    pub url: String,
    pub notes: String,
    pub sort_order: i64,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UpsertLmsPortalInput {
    pub id: Option<String>,
    pub name: String,
    pub url: String,
    pub notes: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LmsImportItemInput {
    pub kind: String,
    pub title: String,
    pub due_at: Option<String>,
    pub course_code: Option<String>,
    pub notes: Option<String>,
    pub lms_item_id: Option<String>,
    pub portal_id: Option<String>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LmsImportResult {
    pub tasks_created: i64,
    pub events_created: i64,
    pub skipped: i64,
}

#[tauri::command]
pub fn lms_list_portals(state: State<'_, AppState>) -> CmdResult<Vec<LmsPortalDto>> {
    state
        .db
        .with_conn(|conn| {
            let mut stmt = conn.prepare(
                "SELECT id, name, url, notes, sort_order FROM lms_portal
                 ORDER BY sort_order ASC, name ASC LIMIT 100",
            )?;
            let rows = stmt
                .query_map([], |r| {
                    Ok(LmsPortalDto {
                        id: r.get(0)?,
                        name: r.get(1)?,
                        url: r.get(2)?,
                        notes: r.get(3)?,
                        sort_order: r.get(4)?,
                    })
                })?
                .collect::<Result<Vec<_>, _>>()?;
            Ok(rows)
        })
        .map_err(Into::into)
}

#[tauri::command]
pub fn lms_upsert_portal(
    app: AppHandle,
    state: State<'_, AppState>,
    input: UpsertLmsPortalInput,
) -> CmdResult<String> {
    let now = Utc::now().to_rfc3339();
    let notes = input.notes.unwrap_or_default();
    let id = if let Some(existing) = input.id.filter(|s| !s.is_empty()) {
        state.db.with_conn(|conn| {
            conn.execute(
                "UPDATE lms_portal SET name = ?1, url = ?2, notes = ?3, updated_at = ?4 WHERE id = ?5",
                rusqlite::params![input.name, input.url, notes, now, existing],
            )?;
            Ok(())
        })?;
        existing
    } else {
        let id = Uuid::new_v4().to_string();
        state.db.with_conn(|conn| {
            let sort: i64 = conn
                .query_row(
                    "SELECT COALESCE(MAX(sort_order), 0) + 1 FROM lms_portal",
                    [],
                    |r| r.get(0),
                )
                .unwrap_or(1);
            conn.execute(
                "INSERT INTO lms_portal (id, name, url, notes, sort_order, created_at, updated_at)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?6)",
                rusqlite::params![id, input.name, input.url, notes, sort, now],
            )?;
            Ok(())
        })?;
        id
    };
    let rev = state.db.bump_revision("lms")?;
    let _ = app.emit(
        "db:change",
        DbChangeEvent {
            domain: "lms".into(),
            revision: rev,
        },
    );
    Ok(id)
}

#[tauri::command]
pub fn lms_delete_portal(
    app: AppHandle,
    state: State<'_, AppState>,
    id: String,
) -> CmdResult<()> {
    clear_portal_credentials(state.inner(), &id);
    state.db.with_conn(|conn| {
        conn.execute("DELETE FROM lms_portal WHERE id = ?1", rusqlite::params![id])?;
        Ok(())
    })?;
    let rev = state.db.bump_revision("lms")?;
    let _ = app.emit(
        "db:change",
        DbChangeEvent {
            domain: "lms".into(),
            revision: rev,
        },
    );
    Ok(())
}

fn bump_lms_calendar(app: &AppHandle, state: &AppState) -> CmdResult<()> {
    let rev_planner = state.db.bump_revision("planner")?;
    let _ = app.emit(
        "db:change",
        DbChangeEvent {
            domain: "planner".into(),
            revision: rev_planner,
        },
    );
    let rev_calendar = state.db.bump_revision("calendar")?;
    let _ = app.emit(
        "db:change",
        DbChangeEvent {
            domain: "calendar".into(),
            revision: rev_calendar,
        },
    );
    Ok(())
}

/// Import LMS-scraped assignments/announcements into planner tasks and calendar events.
#[tauri::command]
pub fn lms_import_items(
    app: AppHandle,
    state: State<'_, AppState>,
    items: Vec<LmsImportItemInput>,
) -> CmdResult<LmsImportResult> {
    let now = Utc::now().to_rfc3339();
    let mut tasks_created = 0i64;
    let mut events_created = 0i64;
    let mut skipped = 0i64;

    state.db.with_conn(|conn| {
        let semester_id: Option<String> = conn
            .query_row(
                "SELECT id FROM planner_semester ORDER BY is_current DESC, sort_order ASC LIMIT 1",
                [],
                |r| r.get(0),
            )
            .ok();

        for item in items {
            let title = item.title.trim();
            if title.is_empty() {
                skipped += 1;
                continue;
            }
            let kind = item.kind.trim().to_ascii_lowercase();
            let notes = item.notes.unwrap_or_default();
            let lms_item_id = item.lms_item_id.unwrap_or_default();

            if kind == "assignment" || kind == "task" {
                if !lms_item_id.is_empty() {
                    let exists: i64 = conn
                        .query_row(
                            "SELECT COUNT(*) FROM planner_task WHERE lms_item_id = ?1",
                            rusqlite::params![lms_item_id],
                            |r| r.get(0),
                        )
                        .unwrap_or(0);
                    if exists > 0 {
                        skipped += 1;
                        continue;
                    }
                }
                let task_id = Uuid::new_v4().to_string();
                let note_text = if notes.is_empty() {
                    item.course_code.unwrap_or_default()
                } else {
                    format!(
                        "{}{}",
                        item.course_code
                            .filter(|c| !c.is_empty())
                            .map(|c| format!("{c} · "))
                            .unwrap_or_default(),
                        notes
                    )
                };
                conn.execute(
                    "INSERT INTO planner_task
                     (id, semester_id, course_id, title, due_at, is_complete, notes, lms_item_id)
                     VALUES (?1, ?2, NULL, ?3, ?4, 0, ?5, ?6)",
                    rusqlite::params![
                        task_id,
                        semester_id,
                        title,
                        item.due_at,
                        note_text,
                        lms_item_id
                    ],
                )?;
                tasks_created += 1;
            } else if kind == "announcement" || kind == "event" {
                if !lms_item_id.is_empty() {
                    let exists: i64 = conn
                        .query_row(
                            "SELECT COUNT(*) FROM calendar_event WHERE provider_event_id = ?1",
                            rusqlite::params![lms_item_id],
                            |r| r.get(0),
                        )
                        .unwrap_or(0);
                    if exists > 0 {
                        skipped += 1;
                        continue;
                    }
                }
                let start = item
                    .due_at
                    .clone()
                    .filter(|s| !s.is_empty())
                    .unwrap_or_else(|| now.clone());
                let event_id = Uuid::new_v4().to_string();
                conn.execute(
                    "INSERT INTO calendar_event
                     (id, title, start_at, end_at, all_day, location, notes, provider,
                      provider_event_id, semester_id, course_id, color_hex, created_at, updated_at)
                     VALUES (?1, ?2, ?3, NULL, 0, '', ?4, 'lms_import', ?5, NULL, NULL, NULL, ?6, ?6)",
                    rusqlite::params![event_id, title, start, notes, lms_item_id, now],
                )?;
                events_created += 1;
            } else {
                skipped += 1;
            }
        }
        Ok(())
    })?;

    bump_lms_calendar(&app, &state)?;
    Ok(LmsImportResult {
        tasks_created,
        events_created,
        skipped,
    })
}

/// Evaluate the LMS extract script in an open College portal window.
#[tauri::command]
pub async fn lms_extract_portal_page(app: AppHandle, portal_id: String) -> CmdResult<String> {
    use std::sync::{Arc, Mutex};
    use tauri::Manager;

    let label = format!("lms-{portal_id}");
    let webview = app
        .get_webview_window(&label)
        .ok_or_else(|| anyhow::anyhow!("Open the portal in a College window first"))?;

    let script = include_str!("lms_extract.js");
    let result = Arc::new(Mutex::new(None::<String>));
    let result_cb = result.clone();

    webview
        .eval_with_callback(script, move |json| {
            if let Ok(mut guard) = result_cb.lock() {
                *guard = Some(json);
            }
        })
        .map_err(|e| anyhow::anyhow!(e))?;

    for _ in 0..60 {
        if result.lock().ok().and_then(|g| g.clone()).is_some() {
            break;
        }
        tokio::time::sleep(std::time::Duration::from_millis(100)).await;
    }

    result
        .lock()
        .ok()
        .and_then(|g| g.clone())
        .ok_or_else(|| anyhow::anyhow!("Page scan timed out").into())
}

/// Navigate the open LMS portal window (back / forward / reload).
#[tauri::command]
pub fn lms_portal_navigate(
    app: AppHandle,
    portal_id: String,
    action: String,
) -> CmdResult<()> {
    use tauri::Manager;

    let label = format!("lms-{portal_id}");
    let webview = app
        .get_webview_window(&label)
        .ok_or_else(|| anyhow::anyhow!("Open the portal in a College window first"))?;

    let script = match action.as_str() {
        "back" => "history.back()",
        "forward" => "history.forward()",
        "reload" => "location.reload()",
        other => return Err(anyhow::anyhow!("unknown navigation action: {other}").into()),
    };
    webview.eval(script).map_err(|e| anyhow::anyhow!(e))?;
    Ok(())
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LmsFindResult {
    pub found: bool,
    pub match_count: i64,
}

/// Find text in the open LMS portal window (WKWebView find substitute with highlight).
#[tauri::command]
pub async fn lms_portal_find(
    app: AppHandle,
    portal_id: String,
    query: String,
    forward: Option<bool>,
) -> CmdResult<LmsFindResult> {
    use std::sync::{Arc, Mutex};
    use tauri::Manager;

    let label = format!("lms-{portal_id}");
    let webview = app
        .get_webview_window(&label)
        .ok_or_else(|| anyhow::anyhow!("Open the portal in a College window first"))?;
    let q = query
        .replace('\\', "\\\\")
        .replace('\'', "\\'")
        .replace('\n', " ");
    let forward = forward.unwrap_or(true);
    let reverse = if forward { "false" } else { "true" };
    let script = format!(
        r#"(function() {{
  var q = '{q}';
  if (!q) return JSON.stringify({{ found: false, matchCount: 0 }});
  try {{
    if (window.getSelection) {{
      var sel = window.getSelection();
      if (sel && sel.removeAllRanges) sel.removeAllRanges();
    }}
  }} catch (e) {{}}
  var found = false;
  var matchCount = 0;
  if (typeof window.find === 'function') {{
    found = window.find(q, false, {reverse}, true, false, false, false);
    try {{
      var needle = q.toLowerCase();
      var walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
      var node;
      while ((node = walker.nextNode())) {{
        var t = (node.nodeValue || '').toLowerCase();
        var idx = 0;
        while ((idx = t.indexOf(needle, idx)) >= 0) {{
          matchCount++;
          idx += needle.length;
        }}
      }}
    }} catch (e2) {{
      matchCount = found ? 1 : 0;
    }}
  }}
  return JSON.stringify({{ found: found, matchCount: matchCount }});
}})()"#,
        q = q,
        reverse = reverse
    );
    let result = Arc::new(Mutex::new(None::<String>));
    let result_cb = result.clone();
    webview
        .eval_with_callback(script, move |json| {
            if let Ok(mut guard) = result_cb.lock() {
                *guard = Some(json);
            }
        })
        .map_err(|e| anyhow::anyhow!(e))?;

    for _ in 0..20 {
        if result.lock().ok().and_then(|g| g.clone()).is_some() {
            break;
        }
        tokio::time::sleep(std::time::Duration::from_millis(50)).await;
    }
    let raw = result
        .lock()
        .ok()
        .and_then(|g| g.clone())
        .unwrap_or_else(|| r#"{"found":false,"matchCount":0}"#.to_string());
    let parsed: serde_json::Value = serde_json::from_str(&raw).unwrap_or_default();
    Ok(LmsFindResult {
        found: parsed.get("found").and_then(|v| v.as_bool()).unwrap_or(false),
        match_count: parsed
            .get("matchCount")
            .and_then(|v| v.as_i64())
            .unwrap_or(0),
    })
}

const LMS_SECRET_NS: &str = "lms.portal";

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LmsCanvasConfigDto {
    pub base_url: String,
    pub connected: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub auth_method: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LmsCanvasSetConfigInput {
    pub base_url: String,
    pub access_token: String,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LmsCanvasSyncResult {
    pub tasks_created: i64,
    pub events_created: i64,
    pub skipped: i64,
    pub courses_fetched: i64,
}

fn load_canvas_secret(state: &AppState) -> CmdResult<Option<super::lms_canvas_oauth::CanvasSecretConfig>> {
    super::lms_canvas_oauth::load_canvas_config(state)
}

fn save_canvas_secret(
    state: &AppState,
    config: &super::lms_canvas_oauth::CanvasSecretConfig,
) -> CmdResult<()> {
    super::lms_canvas_oauth::save_canvas_config(state, config)
}

#[tauri::command]
pub fn lms_canvas_get_config(state: State<'_, AppState>) -> CmdResult<LmsCanvasConfigDto> {
    let config = load_canvas_secret(state.inner())?;
    Ok(LmsCanvasConfigDto {
        base_url: config
            .as_ref()
            .map(|c| c.base_url.clone())
            .unwrap_or_default(),
        connected: config
            .as_ref()
            .map(|c| !c.access_token.trim().is_empty())
            .unwrap_or(false),
        auth_method: config.as_ref().and_then(|c| {
            if c.refresh_token.is_some() {
                Some("oauth".into())
            } else if !c.access_token.is_empty() {
                Some("token".into())
            } else {
                None
            }
        }),
    })
}

#[tauri::command]
pub fn lms_canvas_set_config(
    state: State<'_, AppState>,
    input: LmsCanvasSetConfigInput,
) -> CmdResult<()> {
    let base_url = super::lms_canvas_oauth::normalize_canvas_base_url(&input.base_url);
    if base_url.is_empty() {
        return Err(anyhow::anyhow!("Canvas base URL required").into());
    }
    let access_token = input.access_token.trim().to_string();
    if access_token.is_empty() {
        let existing = load_canvas_secret(state.inner())?;
        let kept = existing
            .as_ref()
            .map(|c| c.access_token.clone())
            .filter(|t| !t.is_empty())
            .ok_or_else(|| anyhow::anyhow!("Canvas access token required"))?;
        save_canvas_secret(
            state.inner(),
            &super::lms_canvas_oauth::CanvasSecretConfig {
                base_url,
                access_token: kept,
                refresh_token: existing.as_ref().and_then(|c| c.refresh_token.clone()),
            },
        )
    } else {
        save_canvas_secret(
            state.inner(),
            &super::lms_canvas_oauth::CanvasSecretConfig {
                base_url,
                access_token,
                refresh_token: None,
            },
        )
    }
}

#[derive(Debug, Deserialize)]
struct CanvasCourse {
    id: i64,
    name: Option<String>,
    course_code: Option<String>,
}

#[derive(Debug, Deserialize)]
struct CanvasAssignment {
    id: i64,
    name: Option<String>,
    due_at: Option<String>,
    html_url: Option<String>,
}

#[tauri::command]
pub async fn lms_canvas_sync(
    app: AppHandle,
    state: State<'_, AppState>,
) -> CmdResult<LmsCanvasSyncResult> {
    let config = load_canvas_secret(state.inner())?
        .filter(|c| !c.base_url.is_empty() && !c.access_token.trim().is_empty())
        .ok_or_else(|| anyhow::anyhow!("Canvas is not configured — add base URL and access token"))?;

    let client = reqwest::Client::builder()
        .user_agent("CollegeDesktop/0.1")
        .timeout(std::time::Duration::from_secs(30))
        .build()
        .map_err(|e| anyhow::anyhow!(e))?;

    let courses_url = format!(
        "{}/api/v1/courses?enrollment_state=active&per_page=100",
        config.base_url.trim_end_matches('/')
    );
    let courses_resp = client
        .get(&courses_url)
        .header(
            reqwest::header::AUTHORIZATION,
            format!("Bearer {}", config.access_token.trim()),
        )
        .send()
        .await
        .map_err(|e| anyhow::anyhow!("Canvas courses fetch failed: {e}"))?;
    if !courses_resp.status().is_success() {
        return Err(anyhow::anyhow!(
            "Canvas courses HTTP {} — check base URL and token",
            courses_resp.status()
        )
        .into());
    }
    let courses: Vec<CanvasCourse> = courses_resp
        .json()
        .await
        .map_err(|e| anyhow::anyhow!("Canvas courses parse failed: {e}"))?;

    let mut import_items: Vec<LmsImportItemInput> = Vec::new();
    for course in &courses {
        let course_label = course
            .course_code
            .as_deref()
            .filter(|s| !s.is_empty())
            .or(course.name.as_deref())
            .unwrap_or("Course")
            .to_string();
        let assignments_url = format!(
            "{}/api/v1/courses/{}/assignments?per_page=100",
            config.base_url.trim_end_matches('/'),
            course.id
        );
        let assignments_resp = client
            .get(&assignments_url)
            .header(
                reqwest::header::AUTHORIZATION,
                format!("Bearer {}", config.access_token.trim()),
            )
            .send()
            .await
            .map_err(|e| anyhow::anyhow!("Canvas assignments fetch failed: {e}"))?;
        if !assignments_resp.status().is_success() {
            continue;
        }
        let assignments: Vec<CanvasAssignment> = assignments_resp
            .json()
            .await
            .unwrap_or_default();
        for assignment in assignments {
            let title = assignment
                .name
                .unwrap_or_else(|| "Assignment".to_string())
                .trim()
                .to_string();
            if title.is_empty() {
                continue;
            }
            import_items.push(LmsImportItemInput {
                kind: "assignment".to_string(),
                title,
                due_at: assignment.due_at,
                course_code: Some(course_label.clone()),
                notes: assignment.html_url,
                lms_item_id: Some(format!("canvas:{}:{}", course.id, assignment.id)),
                portal_id: None,
            });
        }
    }

    let courses_fetched = courses.len() as i64;
    let import_result = lms_import_items(app, state, import_items)?;
    Ok(LmsCanvasSyncResult {
        tasks_created: import_result.tasks_created,
        events_created: import_result.events_created,
        skipped: import_result.skipped,
        courses_fetched,
    })
}

fn portal_user_key(portal_id: &str) -> String {
    format!("{portal_id}.user")
}

fn portal_pass_key(portal_id: &str) -> String {
    format!("{portal_id}.pass")
}

fn clear_portal_credentials(state: &AppState, portal_id: &str) {
    let _ = state
        .security
        .delete_secret(LMS_SECRET_NS, &portal_user_key(portal_id));
    let _ = state
        .security
        .delete_secret(LMS_SECRET_NS, &portal_pass_key(portal_id));
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LmsPortalCredentialsDto {
    pub username: String,
    pub has_password: bool,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LmsPortalCredentialsInput {
    pub portal_id: String,
    pub username: String,
    pub password: String,
}

#[tauri::command]
pub fn lms_portal_credentials_get(
    state: State<'_, AppState>,
    portal_id: String,
) -> CmdResult<LmsPortalCredentialsDto> {
    let user = state
        .security
        .get_secret(LMS_SECRET_NS, &portal_user_key(&portal_id))?
        .and_then(|b| String::from_utf8(b).ok())
        .unwrap_or_default();
    let has_password = state
        .security
        .get_secret(LMS_SECRET_NS, &portal_pass_key(&portal_id))?
        .map(|b| !b.is_empty())
        .unwrap_or(false);
    Ok(LmsPortalCredentialsDto {
        username: user,
        has_password,
    })
}

#[tauri::command]
pub fn lms_portal_credentials_set(
    state: State<'_, AppState>,
    input: LmsPortalCredentialsInput,
) -> CmdResult<()> {
    let portal_id = input.portal_id.trim();
    if portal_id.is_empty() {
        return Err(anyhow::anyhow!("portalId required").into());
    }
    state.security.set_secret(
        LMS_SECRET_NS,
        &portal_user_key(portal_id),
        input.username.trim().as_bytes(),
    )?;
    if !input.password.is_empty() {
        state.security.set_secret(
            LMS_SECRET_NS,
            &portal_pass_key(portal_id),
            input.password.as_bytes(),
        )?;
    }
    Ok(())
}

#[tauri::command]
pub fn lms_portal_credentials_clear(
    state: State<'_, AppState>,
    portal_id: String,
) -> CmdResult<()> {
    clear_portal_credentials(state.inner(), &portal_id);
    Ok(())
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LmsAutofillLoginResult {
    pub filled_username: bool,
    pub filled_password: bool,
}

/// Fill username/password on the open LMS College window (WK document-start substitute).
#[tauri::command]
pub async fn lms_portal_autofill_login(
    app: AppHandle,
    state: State<'_, AppState>,
    portal_id: String,
) -> CmdResult<LmsAutofillLoginResult> {
    use std::sync::{Arc, Mutex};
    use tauri::Manager;

    let username = state
        .security
        .get_secret(LMS_SECRET_NS, &portal_user_key(&portal_id))?
        .and_then(|b| String::from_utf8(b).ok())
        .unwrap_or_default();
    let password = state
        .security
        .get_secret(LMS_SECRET_NS, &portal_pass_key(&portal_id))?
        .and_then(|b| String::from_utf8(b).ok())
        .unwrap_or_default();
    if username.trim().is_empty() && password.is_empty() {
        return Err(anyhow::anyhow!("No saved login for this portal — edit the portal and save credentials").into());
    }

    let label = format!("lms-{portal_id}");
    let webview = app
        .get_webview_window(&label)
        .ok_or_else(|| anyhow::anyhow!("Open the portal in a College window first"))?;

    let user_js = serde_json::to_string(&username).unwrap_or_else(|_| "\"\"".into());
    let pass_js = serde_json::to_string(&password).unwrap_or_else(|_| "\"\"".into());
    let script = format!(
        r#"(function() {{
  var user = {user_js};
  var pass = {pass_js};
  function scoreUser(el) {{
    var hay = ((el.name || '') + ' ' + (el.id || '') + ' ' + (el.autocomplete || '') + ' ' + (el.placeholder || '') + ' ' + (el.getAttribute('aria-label') || '')).toLowerCase();
    var t = (el.type || 'text').toLowerCase();
    if (t === 'email' || hay.indexOf('email') >= 0) return 3;
    if (hay.indexOf('user') >= 0 || hay.indexOf('login') >= 0 || hay.indexOf('netid') >= 0) return 2;
    if (t === 'text') return 1;
    return 0;
  }}
  function setVal(el, v) {{
    if (!el || v == null) return false;
    var proto = el.tagName === 'TEXTAREA' ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
    var desc = Object.getOwnPropertyDescriptor(proto, 'value');
    if (desc && desc.set) desc.set.call(el, String(v));
    else el.value = String(v);
    el.dispatchEvent(new Event('input', {{ bubbles: true }}));
    el.dispatchEvent(new Event('change', {{ bubbles: true }}));
    return true;
  }}
  var inputs = Array.prototype.slice.call(document.querySelectorAll('input'));
  var userEl = null, userScore = 0;
  inputs.forEach(function (el) {{
    if (el.disabled || el.readOnly) return;
    var s = scoreUser(el);
    if (s > userScore) {{ userScore = s; userEl = el; }}
  }});
  var passEl = inputs.find(function (el) {{
    return (el.type || '').toLowerCase() === 'password' && !el.disabled && !el.readOnly;
  }}) || null;
  var filledUsername = false, filledPassword = false;
  if (user && userEl) filledUsername = setVal(userEl, user);
  if (pass && passEl) filledPassword = setVal(passEl, pass);
  return JSON.stringify({{ filledUsername: filledUsername, filledPassword: filledPassword }});
}})()"#,
        user_js = user_js,
        pass_js = pass_js
    );

    let result = Arc::new(Mutex::new(None::<String>));
    let result_cb = result.clone();
    webview
        .eval_with_callback(script, move |json| {
            if let Ok(mut guard) = result_cb.lock() {
                *guard = Some(json);
            }
        })
        .map_err(|e| anyhow::anyhow!(e))?;

    for _ in 0..40 {
        if result.lock().ok().and_then(|g| g.clone()).is_some() {
            break;
        }
        tokio::time::sleep(std::time::Duration::from_millis(50)).await;
    }
    let raw = result
        .lock()
        .ok()
        .and_then(|g| g.clone())
        .unwrap_or_else(|| r#"{"filledUsername":false,"filledPassword":false}"#.to_string());
    let parsed: serde_json::Value = serde_json::from_str(&raw).unwrap_or_default();
    Ok(LmsAutofillLoginResult {
        filled_username: parsed
            .get("filledUsername")
            .and_then(|v| v.as_bool())
            .unwrap_or(false),
        filled_password: parsed
            .get("filledPassword")
            .and_then(|v| v.as_bool())
            .unwrap_or(false),
    })
}

/// Document-start substitute: inject LMS extract helpers into the open College window.
#[tauri::command]
pub fn lms_portal_install_bridge(app: AppHandle, portal_id: String) -> CmdResult<()> {
    use tauri::Manager;

    let label = format!("lms-{portal_id}");
    let webview = app
        .get_webview_window(&label)
        .ok_or_else(|| anyhow::anyhow!("Open the portal in a College window first"))?;
    let extract = include_str!("lms_extract.js");
    let mut script = String::from(
        "(function() {
  if (window.__collegeLmsBridgeInstalled) return true;
  window.__collegeLmsBridgeInstalled = true;
  try {
",
    );
    script.push_str(extract);
    script.push_str(
        "
  } catch (e) {
    console.warn('College LMS bridge install failed', e);
  }
  return true;
})()",
    );
    webview.eval(&script).map_err(|e| anyhow::anyhow!(e))?;
    Ok(())
}
