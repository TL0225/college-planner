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
