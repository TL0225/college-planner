//! Career Apply autofill — Greenhouse/Lever Tier A + Workday/iCIMS Tier B + Oracle/Talemetry Tier C inventory.

use crate::commands::CmdResult;
use crate::AppState;
use base64::{engine::general_purpose::STANDARD as BASE64, Engine as _};
use rusqlite::OptionalExtension;
use serde::{Deserialize, Serialize};
use tauri::{AppHandle, State};

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CareerApplyPayloadDto {
    pub personal: CareerApplyPersonalDto,
    pub application_profile: CareerApplyProfileDto,
    pub platform: String,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CareerApplyPersonalDto {
    pub first_name: String,
    pub last_name: String,
    pub full_name: String,
    pub email: String,
    pub phone: String,
    pub linked_in_url: String,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CareerApplyProfileDto {
    pub work_authorization: CareerApplyWorkAuthDto,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CareerApplyWorkAuthDto {
    pub us_authorized: Option<bool>,
    pub requires_sponsorship_now: Option<bool>,
    pub requires_sponsorship_future: Option<bool>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CareerApplyAutofillResult {
    pub platform: String,
    pub fields: Vec<CareerApplyFieldResult>,
    pub write_attempt_count: i64,
    pub filled_count: i64,
}

#[derive(Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CareerApplyFieldResult {
    pub payload_key: String,
    pub intended: String,
    pub filled: Option<String>,
    pub verified: bool,
    pub status: String,
    pub ats_label: String,
}

#[derive(Debug, Deserialize)]
struct AutofillReport {
    fields: Vec<CareerApplyFieldResult>,
    #[serde(rename = "writeAttemptCount")]
    write_attempt_count: i64,
}

pub fn detect_apply_platform(url: &str) -> Option<&'static str> {
    let lower = url.to_ascii_lowercase();
    if lower.contains("greenhouse.io") || lower.contains("boards.greenhouse.io") {
        Some("greenhouse")
    } else if lower.contains("lever.co") || lower.contains("jobs.lever.co") {
        Some("lever")
    } else if lower.contains("myworkdayjobs.com") || lower.contains("workday.com/en-us/jobs") {
        Some("workday")
    } else if lower.contains("icims.com") || lower.contains("jobs.icims.com") {
        Some("icims")
    } else if lower.contains("oraclecloud.com")
        || lower.contains("taleo.net")
        || lower.contains("taleo.com")
    {
        Some("oracle")
    } else if lower.contains("talemetry.com") || lower.contains("jobvite.com") {
        Some("talemetry")
    } else if lower.contains("usajobs.gov") {
        Some("usajobs")
    } else {
        None
    }
}

fn split_name(full_name: &str) -> (String, String) {
    let trimmed = full_name.trim();
    if trimmed.is_empty() {
        return (String::new(), String::new());
    }
    let mut parts = trimmed.split_whitespace();
    let first = parts.next().unwrap_or("").to_string();
    let last = parts.collect::<Vec<_>>().join(" ");
    (first, last)
}

fn setting_bool(conn: &rusqlite::Connection, key: &str) -> Option<bool> {
    let raw: String = conn
        .query_row(
            "SELECT value FROM app_settings WHERE key = ?1 LIMIT 1",
            [key],
            |r| r.get(0),
        )
        .ok()?;
    match raw.trim().to_ascii_lowercase().as_str() {
        "true" | "1" | "yes" => Some(true),
        "false" | "0" | "no" => Some(false),
        _ => None,
    }
}

#[tauri::command]
pub fn career_apply_build_payload(state: State<'_, AppState>) -> CmdResult<CareerApplyPayloadDto> {
    state
        .db
        .with_conn(|conn| {
            let row: Option<(String, String, String)> = conn
                .query_row(
                    "SELECT full_name, email, phone FROM profile ORDER BY updated_at DESC LIMIT 1",
                    [],
                    |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)),
                )
                .optional()?;
            let (full_name, email, phone) = row.unwrap_or_default();
            let linked_in_url: String = conn
                .query_row(
                    "SELECT value FROM app_settings WHERE key = 'profile.linkedInURL' LIMIT 1",
                    [],
                    |r| r.get(0),
                )
                .unwrap_or_default();
            let (first_name, last_name) = split_name(&full_name);
            Ok(CareerApplyPayloadDto {
                personal: CareerApplyPersonalDto {
                    first_name,
                    last_name,
                    full_name: full_name.clone(),
                    email,
                    phone,
                    linked_in_url,
                },
                application_profile: CareerApplyProfileDto {
                    work_authorization: CareerApplyWorkAuthDto {
                        us_authorized: setting_bool(conn, "career.apply.usAuthorized"),
                        requires_sponsorship_now: setting_bool(
                            conn,
                            "career.apply.requiresSponsorshipNow",
                        ),
                        requires_sponsorship_future: setting_bool(
                            conn,
                            "career.apply.requiresSponsorshipFuture",
                        ),
                    },
                },
                platform: String::new(),
            })
        })
        .map_err(Into::into)
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CareerApplyRunAutofillInput {
    pub application_id: String,
    pub url: Option<String>,
}

#[tauri::command]
pub async fn career_apply_run_autofill(
    app: AppHandle,
    state: State<'_, AppState>,
    input: CareerApplyRunAutofillInput,
) -> CmdResult<CareerApplyAutofillResult> {
    use std::sync::{Arc, Mutex};
    use tauri::Manager;

    let label = format!("career-apply-{}", input.application_id);
    let webview = app
        .get_webview_window(&label)
        .ok_or_else(|| anyhow::anyhow!("Open the Apply window first"))?;

    let current_url = webview.url().map_err(|e| anyhow::anyhow!(e))?.to_string();
    let url = input
        .url
        .filter(|s| !s.trim().is_empty())
        .unwrap_or(current_url);
    let platform = detect_apply_platform(&url).ok_or_else(|| {
        anyhow::anyhow!(
            "Unsupported ATS — Greenhouse, Lever, Workday, iCIMS, Oracle, and Talemetry are supported"
        )
    })?;
    if platform == "usajobs" {
        return Err(anyhow::anyhow!(
            "USAJobs uses its own apply flow — open the listing and apply on usajobs.gov"
        )
        .into());
    }

    let payload = career_apply_build_payload(state)?;
    let personal_json = serde_json::json!({
        "personal": {
            "firstName": payload.personal.first_name,
            "lastName": payload.personal.last_name,
            "fullName": payload.personal.full_name,
            "email": payload.personal.email,
            "phone": payload.personal.phone,
            "linkedInURL": payload.personal.linked_in_url,
        },
        "applicationProfile": {
            "workAuthorization": {
                "usAuthorized": payload.application_profile.work_authorization.us_authorized,
                "requiresSponsorshipNow": payload
                    .application_profile
                    .work_authorization
                    .requires_sponsorship_now,
                "requiresSponsorshipFuture": payload
                    .application_profile
                    .work_authorization
                    .requires_sponsorship_future,
            }
        }
    });
    let map_json = match platform {
        "greenhouse" => include_str!("career_apply/greenhouse_field_map.v1.json"),
        "lever" => include_str!("career_apply/lever_field_map.v1.json"),
        "workday" => include_str!("career_apply/workday_field_map.v1.json"),
        "icims" => include_str!("career_apply/icims_field_map.v1.json"),
        "oracle" => include_str!("career_apply/oracle_field_map.v1.json"),
        "talemetry" => include_str!("career_apply/talemetry_field_map.v1.json"),
        _ => return Err(anyhow::anyhow!("unknown platform").into()),
    };
    let core = include_str!("career_apply/autofill_core.js");
    let script = format!(
        r#"(function() {{
  window.__collegeApplyPayload = {personal_json};
  window.__collegeApplyMapDef = {map_json};
  {core}
}})()"#
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

    for _ in 0..80 {
        if result.lock().ok().and_then(|g| g.clone()).is_some() {
            break;
        }
        tokio::time::sleep(std::time::Duration::from_millis(100)).await;
    }

    let raw = result
        .lock()
        .ok()
        .and_then(|g| g.clone())
        .ok_or_else(|| anyhow::anyhow!("Autofill timed out"))?;
    let report: AutofillReport = serde_json::from_str(&raw).map_err(|e| anyhow::anyhow!(e))?;
    let filled_count = report
        .fields
        .iter()
        .filter(|f| f.status == "filled")
        .count() as i64;

    Ok(CareerApplyAutofillResult {
        platform: platform.to_string(),
        fields: report.fields,
        write_attempt_count: report.write_attempt_count,
        filled_count,
    })
}

/// Read resume PDF from vault for attach (optional follow-up).
#[allow(dead_code)]
fn read_resume_base64(conn: &rusqlite::Connection, root: &std::path::Path) -> Option<(String, String)> {
    let (title, rel_path): (String, String) = conn
        .query_row(
            "SELECT title, relative_path FROM vault_document
             WHERE is_folder = 0 AND (category = 'resume' OR title LIKE '%resume%')
             ORDER BY updated_at DESC LIMIT 1",
            [],
            |r| Ok((r.get(0)?, r.get(1)?)),
        )
        .optional()
        .ok()
        .flatten()?;
    let path = root.join(rel_path);
    let bytes = std::fs::read(path).ok()?;
    Some((title, BASE64.encode(bytes)))
}


/// Document-start substitute: mark Apply window ready for autofill.
#[tauri::command]
pub fn career_apply_install_bridge(
    app: AppHandle,
    application_id: String,
) -> CmdResult<()> {
    use tauri::Manager;

    let label = format!("career-apply-{application_id}");
    let webview = app
        .get_webview_window(&label)
        .ok_or_else(|| anyhow::anyhow!("Open the Apply window first"))?;
    let script = r#"(function() {
  if (window.__collegeApplyBridgeInstalled) return true;
  window.__collegeApplyBridgeInstalled = true;
  window.__collegeApplyWarm = function () { return true; };
  return true;
})()"#;
    webview.eval(script).map_err(|e| anyhow::anyhow!(e))?;
    Ok(())
}
