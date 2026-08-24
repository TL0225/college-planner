use crate::commands::CmdResult;
use crate::db::DbChangeEvent;
use crate::AppState;
use chrono::Utc;
use rusqlite::OptionalExtension;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use tauri::{AppHandle, Emitter, State};
use uuid::Uuid;

const SCORECARD_API_KEY_SETTING: &str = "discovery.scorecard.apiKey";

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DiscoverySyncFederalResult {
    pub synced: i64,
    pub skipped: i64,
    pub errors: Vec<String>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DiscoveryInstitutionDto {
    pub id: String,
    pub name: String,
    pub unit_id: Option<String>,
    pub state: String,
    pub city: String,
    pub website: String,
    pub is_saved: bool,
    pub admit_rate: Option<f64>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DiscoveryCdsSnapshotDto {
    pub unit_id: String,
    pub academic_year: i32,
    pub source_url: String,
    pub applicants: Option<i64>,
    pub admits: Option<i64>,
    pub enrolled: Option<i64>,
    pub admit_rate: Option<f64>,
    #[serde(rename = "yield")]
    pub yield_rate: Option<f64>,
    pub factor_importance: std::collections::HashMap<String, String>,
    pub test_policy_note: Option<String>,
    pub sat_ebrw25: Option<i64>,
    pub sat_ebrw75: Option<i64>,
    pub sat_math25: Option<i64>,
    pub sat_math75: Option<i64>,
    pub act_composite25: Option<i64>,
    pub act_composite75: Option<i64>,
    pub percent_submitting_sat: Option<f64>,
    pub percent_submitting_act: Option<f64>,
    pub hs_gpa_average: Option<f64>,
    pub hs_gpa_distribution: std::collections::HashMap<String, f64>,
    pub early_decision_applicants: Option<i64>,
    pub early_decision_admits: Option<i64>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DiscoveryProfileDto {
    pub institution: DiscoveryInstitutionDto,
    pub cds: Option<DiscoveryCdsSnapshotDto>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UpdateDiscoveryInstitutionInput {
    pub id: String,
    pub is_saved: Option<bool>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct CdsFixtureFile {
    #[serde(default)]
    academic_year: i32,
    #[serde(default, rename = "sourceURL")]
    source_url: String,
    c1: Option<CdsC1>,
    c7: Option<std::collections::HashMap<String, String>>,
    c8: Option<CdsC8>,
    c9: Option<CdsC9>,
    c11: Option<CdsC11>,
    c21: Option<CdsC21>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct CdsC1 {
    applicants: Option<i64>,
    admits: Option<i64>,
    enrolled: Option<i64>,
    admit_rate: Option<f64>,
    #[serde(rename = "yield")]
    yield_rate: Option<f64>,
}

#[derive(Debug, Deserialize)]
struct CdsC8 {
    #[serde(rename = "testPolicyNote")]
    test_policy_note: Option<String>,
}

#[derive(Debug, Deserialize)]
struct CdsC9 {
    #[serde(rename = "satEBRW25")]
    sat_ebrw25: Option<i64>,
    #[serde(rename = "satEBRW75")]
    sat_ebrw75: Option<i64>,
    #[serde(rename = "satMath25")]
    sat_math25: Option<i64>,
    #[serde(rename = "satMath75")]
    sat_math75: Option<i64>,
    #[serde(rename = "actComposite25")]
    act_composite25: Option<i64>,
    #[serde(rename = "actComposite75")]
    act_composite75: Option<i64>,
    #[serde(rename = "percentSubmittingSAT")]
    percent_submitting_sat: Option<f64>,
    #[serde(rename = "percentSubmittingACT")]
    percent_submitting_act: Option<f64>,
}

#[derive(Debug, Deserialize)]
struct CdsC11 {
    #[serde(rename = "hsGPAAverage")]
    hs_gpa_average: Option<f64>,
    distribution: Option<std::collections::HashMap<String, f64>>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct CdsC21 {
    early_decision_applicants: Option<i64>,
    early_decision_admits: Option<i64>,
}

fn map_institution_row(r: &rusqlite::Row<'_>) -> rusqlite::Result<DiscoveryInstitutionDto> {
    let is_saved: i32 = r.get(6)?;
    Ok(DiscoveryInstitutionDto {
        id: r.get(0)?,
        name: r.get(1)?,
        unit_id: r.get(2)?,
        state: r.get(3)?,
        city: r.get(4)?,
        website: r.get(5)?,
        is_saved: is_saved != 0,
        admit_rate: r.get(7).ok(),
    })
}

const INSTITUTION_SELECT: &str =
    "SELECT i.id, i.name, i.unit_id, i.state, i.city, i.website, i.is_saved,
     (
         SELECT CAST(json_extract(cds.payload_json, '$.c1.admitRate') AS REAL)
         FROM discovery_cds_snapshot cds
         WHERE cds.unit_id = i.unit_id
         ORDER BY cds.year DESC
         LIMIT 1
     ) AS admit_rate
     FROM discovery_institution_identity i";

fn parse_cds_payload(
    unit_id: &str,
    year: i32,
    payload_json: &str,
    source_url_override: Option<&str>,
) -> CmdResult<DiscoveryCdsSnapshotDto> {
    let file: CdsFixtureFile = serde_json::from_str(payload_json).map_err(|e| {
        crate::commands::CommandError {
            message: format!("Invalid CDS payload: {e}"),
        }
    })?;
    Ok(dto_from_fixture(
        &file,
        unit_id,
        year,
        source_url_override.unwrap_or(&file.source_url),
    ))
}

fn dto_from_fixture(
    file: &CdsFixtureFile,
    unit_id: &str,
    year: i32,
    source_url: &str,
) -> DiscoveryCdsSnapshotDto {
    DiscoveryCdsSnapshotDto {
        unit_id: unit_id.to_string(),
        academic_year: if file.academic_year > 0 {
            file.academic_year
        } else {
            year
        },
        source_url: if file.source_url.is_empty() {
            source_url.to_string()
        } else {
            file.source_url.clone()
        },
        applicants: file.c1.as_ref().and_then(|c| c.applicants),
        admits: file.c1.as_ref().and_then(|c| c.admits),
        enrolled: file.c1.as_ref().and_then(|c| c.enrolled),
        admit_rate: file.c1.as_ref().and_then(|c| c.admit_rate),
        yield_rate: file.c1.as_ref().and_then(|c| c.yield_rate),
        factor_importance: file.c7.clone().unwrap_or_default(),
        test_policy_note: file.c8.as_ref().and_then(|c| c.test_policy_note.clone()),
        sat_ebrw25: file.c9.as_ref().and_then(|c| c.sat_ebrw25),
        sat_ebrw75: file.c9.as_ref().and_then(|c| c.sat_ebrw75),
        sat_math25: file.c9.as_ref().and_then(|c| c.sat_math25),
        sat_math75: file.c9.as_ref().and_then(|c| c.sat_math75),
        act_composite25: file.c9.as_ref().and_then(|c| c.act_composite25),
        act_composite75: file.c9.as_ref().and_then(|c| c.act_composite75),
        percent_submitting_sat: file.c9.as_ref().and_then(|c| c.percent_submitting_sat),
        percent_submitting_act: file.c9.as_ref().and_then(|c| c.percent_submitting_act),
        hs_gpa_average: file.c11.as_ref().and_then(|c| c.hs_gpa_average),
        hs_gpa_distribution: file
            .c11
            .as_ref()
            .and_then(|c| c.distribution.clone())
            .unwrap_or_default(),
        early_decision_applicants: file.c21.as_ref().and_then(|c| c.early_decision_applicants),
        early_decision_admits: file.c21.as_ref().and_then(|c| c.early_decision_admits),
    }
}

fn fetch_latest_cds(
    conn: &rusqlite::Connection,
    unit_id: &str,
) -> Result<Option<DiscoveryCdsSnapshotDto>, String> {
    let mut stmt = conn
        .prepare(
            "SELECT year, payload_json FROM discovery_cds_snapshot
         WHERE unit_id = ?1
         ORDER BY year DESC
         LIMIT 1",
        )
        .map_err(|e| e.to_string())?;
    let mut rows = stmt
        .query(rusqlite::params![unit_id])
        .map_err(|e| e.to_string())?;
    if let Some(row) = rows.next().map_err(|e| e.to_string())? {
        let year: i32 = row.get(0).map_err(|e| e.to_string())?;
        let payload: String = row.get(1).map_err(|e| e.to_string())?;
        return parse_cds_payload(unit_id, year, &payload, None)
            .map(Some)
            .map_err(|e| e.message);
    }
    Ok(None)
}

fn bump_discovery(app: &AppHandle, state: &AppState) -> CmdResult<()> {
    let rev = state.db.bump_revision("discovery")?;
    let _ = app.emit(
        "db:change",
        DbChangeEvent {
            domain: "discovery".into(),
            revision: rev,
        },
    );
    Ok(())
}

/// Demo CDS payloads keyed by unit_id — mirrors Swift `cds_196088.json` shape.
pub fn demo_cds_seed_rows() -> Vec<(&'static str, i32, &'static str)> {
    vec![
        (
            "100001",
            2024,
            r#"{
  "academicYear": 2024,
  "sourceURL": "https://www.stateu.edu/common-data-set.html",
  "c1": {
    "applicants": 28450,
    "admits": 18210,
    "enrolled": 3920,
    "admitRate": 0.64,
    "yield": 0.215
  },
  "c7": {
    "gpa": "Very Important",
    "rigor": "Very Important",
    "tests": "Considered",
    "essay": "Important",
    "recommendations": "Important",
    "interview": "Not Considered",
    "extracurriculars": "Important"
  },
  "c8": {
    "testPolicyNote": "SAT/ACT optional for most first-year applicants."
  },
  "c9": {
    "satEBRW25": 560,
    "satEBRW75": 640,
    "satMath25": 570,
    "satMath75": 660,
    "actComposite25": 24,
    "actComposite75": 29,
    "percentSubmittingSAT": 0.68,
    "percentSubmittingACT": 0.31
  },
  "c11": {
    "hsGPAAverage": 3.65,
    "distribution": {
      "4.0": 0.18,
      "3.75-3.99": 0.36,
      "3.50-3.74": 0.26,
      "3.25-3.49": 0.13,
      "below_3.25": 0.07
    }
  }
}"#,
        ),
        (
            "100002",
            2024,
            r#"{
  "academicYear": 2024,
  "sourceURL": "https://www.coastaltech.edu/admissions/cds",
  "c1": {
    "applicants": 41200,
    "admits": 12480,
    "enrolled": 2680,
    "admitRate": 0.303,
    "yield": 0.215
  },
  "c7": {
    "gpa": "Very Important",
    "rigor": "Very Important",
    "tests": "Important",
    "essay": "Considered",
    "recommendations": "Considered",
    "interview": "Not Considered",
    "extracurriculars": "Considered"
  },
  "c8": {
    "testPolicyNote": "Test scores required for most applicants; see site for exceptions."
  },
  "c9": {
    "satEBRW25": 610,
    "satEBRW75": 690,
    "satMath25": 620,
    "satMath75": 710,
    "actComposite25": 27,
    "actComposite75": 32,
    "percentSubmittingSAT": 0.81,
    "percentSubmittingACT": 0.42
  },
  "c11": {
    "hsGPAAverage": 3.82,
    "distribution": {
      "4.0": 0.28,
      "3.75-3.99": 0.41,
      "3.50-3.74": 0.2,
      "3.25-3.49": 0.08,
      "below_3.25": 0.03
    }
  },
  "c21": {
    "earlyDecisionApplicants": 4200,
    "earlyDecisionAdmits": 1680
  }
}"#,
        ),
    ]
}

pub fn seed_demo_cds(conn: &rusqlite::Connection) -> rusqlite::Result<()> {
    for (unit_id, year, payload) in demo_cds_seed_rows() {
        conn.execute(
            "INSERT OR IGNORE INTO discovery_cds_snapshot (id, unit_id, year, payload_json)
             VALUES (?1, ?2, ?3, ?4)",
            rusqlite::params![Uuid::new_v4().to_string(), unit_id, year, payload],
        )?;
    }
    Ok(())
}

#[tauri::command]
pub fn discovery_list_institutions(
    state: State<'_, AppState>,
    query: Option<String>,
    limit: Option<i64>,
) -> CmdResult<Vec<DiscoveryInstitutionDto>> {
    let limit = limit.unwrap_or(200).clamp(1, 500);
    let q = query.unwrap_or_default().trim().to_string();
    state
        .db
        .with_conn(|conn| {
            let mut rows = Vec::new();
            if q.is_empty() {
                let mut stmt = conn.prepare(&format!(
                    "{INSTITUTION_SELECT}
                     ORDER BY i.name ASC
                     LIMIT ?1"
                ))?;
                let mapped = stmt.query_map(rusqlite::params![limit], map_institution_row)?;
                for row in mapped {
                    rows.push(row?);
                }
            } else {
                let like = format!("%{}%", q);
                let mut stmt = conn.prepare(&format!(
                    "{INSTITUTION_SELECT}
                     WHERE i.name LIKE ?1 OR i.city LIKE ?1 OR i.state LIKE ?1 OR i.website LIKE ?1
                     ORDER BY i.name ASC
                     LIMIT ?2"
                ))?;
                let mapped = stmt.query_map(rusqlite::params![like, limit], map_institution_row)?;
                for row in mapped {
                    rows.push(row?);
                }
            }
            Ok(rows)
        })
        .map_err(Into::into)
}

#[tauri::command]
pub fn discovery_get_profile(
    state: State<'_, AppState>,
    institution_id: String,
) -> CmdResult<DiscoveryProfileDto> {
    state
        .db
        .with_conn(|conn| {
            let mut stmt = conn.prepare(&format!(
                "{INSTITUTION_SELECT}
                 WHERE i.id = ?1"
            ))?;
            let institution = stmt
                .query_row(rusqlite::params![institution_id], map_institution_row)
                .map_err(|e| match e {
                    rusqlite::Error::QueryReturnedNoRows => {
                        rusqlite::Error::InvalidParameterName("Institution not found".into())
                    }
                    other => other,
                })?;

            let cds = match institution.unit_id.as_deref() {
                Some(unit_id) => fetch_latest_cds(conn, unit_id)
                    .map_err(|e| rusqlite::Error::InvalidParameterName(e))?,
                None => None,
            };

            Ok(DiscoveryProfileDto { institution, cds })
        })
        .map_err(Into::into)
}

#[tauri::command]
pub fn discovery_get_cds(state: State<'_, AppState>, unit_id: String) -> CmdResult<Option<DiscoveryCdsSnapshotDto>> {
    state
        .db
        .with_conn(|conn| {
            Ok(fetch_latest_cds(conn, &unit_id)
                .map_err(|e| rusqlite::Error::InvalidParameterName(e))?)
        })
        .map_err(Into::into)
}

#[tauri::command]
pub fn discovery_upsert_institution(
    app: AppHandle,
    state: State<'_, AppState>,
    name: String,
    city: Option<String>,
    state_code: Option<String>,
    website: Option<String>,
) -> CmdResult<String> {
    let id = Uuid::new_v4().to_string();
    state.db.with_conn(|conn| {
        conn.execute(
            "INSERT INTO discovery_institution_identity
             (id, name, unit_id, state, city, website, is_saved)
             VALUES (?1, ?2, NULL, ?3, ?4, ?5, 0)",
            rusqlite::params![
                id,
                name,
                state_code.unwrap_or_default(),
                city.unwrap_or_default(),
                website.unwrap_or_default()
            ],
        )?;
        Ok(())
    })?;
    bump_discovery(&app, &state)?;
    Ok(id)
}

#[tauri::command]
pub fn discovery_update_institution(
    app: AppHandle,
    state: State<'_, AppState>,
    input: UpdateDiscoveryInstitutionInput,
) -> CmdResult<()> {
    state.db.with_conn(|conn| {
        if let Some(is_saved) = input.is_saved {
            conn.execute(
                "UPDATE discovery_institution_identity SET is_saved = ?1 WHERE id = ?2",
                rusqlite::params![if is_saved { 1 } else { 0 }, input.id],
            )?;
        }
        Ok(())
    })?;
    bump_discovery(&app, &state)?;
    Ok(())
}

#[tauri::command]
pub fn discovery_delete_institution(
    app: AppHandle,
    state: State<'_, AppState>,
    id: String,
) -> CmdResult<()> {
    state.db.with_conn(|conn| {
        conn.execute(
            "DELETE FROM discovery_institution_identity WHERE id = ?1",
            rusqlite::params![id],
        )?;
        Ok(())
    })?;
    bump_discovery(&app, &state)?;
    Ok(())
}

fn read_scorecard_api_key(conn: &rusqlite::Connection) -> Option<String> {
    conn.query_row(
        "SELECT value FROM app_settings WHERE key = ?1",
        rusqlite::params![SCORECARD_API_KEY_SETTING],
        |r| r.get(0),
    )
    .optional()
    .ok()
    .flatten()
    .filter(|s: &String| !s.trim().is_empty())
}

fn scorecard_payload_from_result(unit_id: &str, row: &Value) -> Option<(i32, String)> {
    let admit_rate = row
        .get("latest.admissions.admission_rate.overall")
        .and_then(|v| v.as_f64());
    if admit_rate.is_none() {
        return None;
    }
    let year = Utc::now().format("%Y").to_string().parse::<i32>().unwrap_or(2024);
    let school_name = row
        .get("school.name")
        .and_then(|v| v.as_str())
        .unwrap_or("Unknown");
    let payload = serde_json::json!({
        "academicYear": year,
        "sourceURL": format!("https://collegescorecard.ed.gov/school/?{unit_id}"),
        "c1": {
            "admitRate": admit_rate,
            "enrolled": row.get("latest.admissions.enrollment").and_then(|v| v.as_f64()).map(|n| n as i64),
        },
        "c9": {
            "satEBRW25": row.get("latest.admissions.sat_scores.25th_percentile.critical_reading").and_then(|v| v.as_f64()).map(|n| n as i64),
            "satEBRW75": row.get("latest.admissions.sat_scores.75th_percentile.critical_reading").and_then(|v| v.as_f64()).map(|n| n as i64),
            "satMath25": row.get("latest.admissions.sat_scores.25th_percentile.math").and_then(|v| v.as_f64()).map(|n| n as i64),
            "satMath75": row.get("latest.admissions.sat_scores.75th_percentile.math").and_then(|v| v.as_f64()).map(|n| n as i64),
            "actComposite25": row.get("latest.admissions.act_scores.25th_percentile.cumulative").and_then(|v| v.as_f64()).map(|n| n as i64),
            "actComposite75": row.get("latest.admissions.act_scores.75th_percentile.cumulative").and_then(|v| v.as_f64()).map(|n| n as i64),
        },
        "c11": {
            "hsGPAAverage": row.get("latest.admissions.sat_scores.average.overall").and_then(|v| v.as_f64()),
        },
        "scorecardMeta": {
            "schoolName": school_name,
            "syncedAt": Utc::now().to_rfc3339(),
        }
    });
    Some((year, payload.to_string()))
}

fn fetch_scorecard_row(unit_id: &str, api_key: Option<&str>) -> Result<Option<Value>, String> {
    let fields = [
        "id",
        "school.name",
        "latest.admissions.admission_rate.overall",
        "latest.admissions.enrollment",
        "latest.admissions.sat_scores.25th_percentile.critical_reading",
        "latest.admissions.sat_scores.75th_percentile.critical_reading",
        "latest.admissions.sat_scores.25th_percentile.math",
        "latest.admissions.sat_scores.75th_percentile.math",
        "latest.admissions.act_scores.25th_percentile.cumulative",
        "latest.admissions.act_scores.75th_percentile.cumulative",
    ]
    .join(",");
    let mut url = format!(
        "https://api.data.gov/ed/collegescorecard/v1/schools?id={unit_id}&fields={fields}&per_page=1"
    );
    if let Some(key) = api_key.filter(|k| !k.is_empty()) {
        url.push_str(&format!("&api_key={}", urlencoding::encode(key)));
    }
    let client = reqwest::blocking::Client::builder()
        .timeout(std::time::Duration::from_secs(20))
        .build()
        .map_err(|e| e.to_string())?;
    let resp = client.get(&url).send().map_err(|e| e.to_string())?;
    if !resp.status().is_success() {
        return Err(format!("HTTP {}", resp.status()));
    }
    let body: Value = resp.json().map_err(|e| e.to_string())?;
    Ok(body
        .get("results")
        .and_then(|v| v.as_array())
        .and_then(|arr| arr.first())
        .cloned())
}

#[tauri::command]
pub fn discovery_sync_federal_data(
    app: AppHandle,
    state: State<'_, AppState>,
) -> CmdResult<DiscoverySyncFederalResult> {
    let mut synced = 0i64;
    let mut skipped = 0i64;
    let mut errors = Vec::new();

    let (institutions, api_key) = state.db.with_conn(|conn| {
        let api_key = read_scorecard_api_key(conn);
        let mut stmt = conn.prepare(
            "SELECT unit_id, name FROM discovery_institution_identity
             WHERE unit_id IS NOT NULL AND TRIM(unit_id) != ''",
        )?;
        let rows = stmt.query_map([], |r| Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?)))?;
        let mut out = Vec::new();
        for row in rows {
            out.push(row?);
        }
        Ok((out, api_key))
    })?;

    for (unit_id, name) in institutions {
        match fetch_scorecard_row(&unit_id, api_key.as_deref()) {
            Ok(Some(row)) => {
                let Some((year, payload_json)) = scorecard_payload_from_result(&unit_id, &row) else {
                    skipped += 1;
                    continue;
                };
                if let Err(e) = state.db.with_conn(|conn| {
                    conn.execute(
                        "INSERT INTO discovery_cds_snapshot (id, unit_id, year, payload_json)
                         VALUES (?1, ?2, ?3, ?4)
                         ON CONFLICT(unit_id, year) DO UPDATE SET payload_json = excluded.payload_json",
                        rusqlite::params![Uuid::new_v4().to_string(), unit_id, year, payload_json],
                    )?;
                    Ok(())
                }) {
                    errors.push(format!("{name}: failed to save CDS ({e})"));
                    skipped += 1;
                } else {
                    synced += 1;
                }
            }
            Ok(None) => {
                skipped += 1;
            }
            Err(e) => {
                errors.push(format!("{name} ({unit_id}): {e}"));
                skipped += 1;
            }
        }
    }

    if synced > 0 {
        bump_discovery(&app, &state)?;
    }

    Ok(DiscoverySyncFederalResult {
        synced,
        skipped,
        errors,
    })
}
