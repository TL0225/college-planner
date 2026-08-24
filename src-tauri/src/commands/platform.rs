use crate::commands::CmdResult;
use crate::AppState;
use serde::{Deserialize, Serialize};
use std::process::Command;
use tauri::State;

#[derive(Debug, Deserialize)]
struct OpenMeteoResponse {
    current: Option<OpenMeteoCurrent>,
}

#[derive(Debug, Deserialize)]
struct OpenMeteoCurrent {
    temperature_2m: Option<f64>,
    weather_code: Option<i64>,
    wind_speed_10m: Option<f64>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct WeatherSnapshot {
    pub temperature_f: f64,
    pub summary: String,
    pub wind_mph: Option<f64>,
    pub source: String,
}

fn weather_code_label(code: i64) -> &'static str {
    match code {
        0 => "Clear",
        1..=3 => "Partly cloudy",
        45 | 48 => "Fog",
        51..=57 => "Drizzle",
        61..=67 => "Rain",
        71..=77 => "Snow",
        80..=82 => "Showers",
        85..=86 => "Snow showers",
        95..=99 => "Thunderstorm",
        _ => "Weather",
    }
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PlatformInfo {
    pub os: String,
    pub arch: String,
    pub family: String,
    pub app_version: String,
}

#[tauri::command]
pub fn get_platform_info() -> PlatformInfo {
    PlatformInfo {
        os: std::env::consts::OS.to_string(),
        arch: std::env::consts::ARCH.to_string(),
        family: std::env::consts::FAMILY.to_string(),
        app_version: env!("CARGO_PKG_VERSION").to_string(),
    }
}

#[tauri::command]
pub fn get_storage_paths(state: State<'_, AppState>) -> CmdResult<crate::paths::StoragePathsDto> {
    Ok(state.paths.to_dto())
}

/// Whether the Typst CLI is available on PATH (resume PDF export).
#[tauri::command]
pub fn platform_typst_available() -> bool {
    Command::new("typst")
        .arg("--version")
        .output()
        .map(|o| o.status.success())
        .unwrap_or(false)
}

/// Open-Meteo snapshot for Overview weather widget (no API key).
#[tauri::command]
pub fn platform_fetch_weather(lat: f64, lon: f64) -> CmdResult<WeatherSnapshot> {
    let url = format!(
        "https://api.open-meteo.com/v1/forecast?latitude={lat}&longitude={lon}&current=temperature_2m,weather_code,wind_speed_10m&temperature_unit=fahrenheit&wind_speed_unit=mph"
    );
    let body: OpenMeteoResponse = reqwest::blocking::Client::builder()
        .timeout(std::time::Duration::from_secs(8))
        .build()
        .map_err(|e| crate::commands::CommandError {
            message: e.to_string(),
        })?
        .get(&url)
        .send()
        .map_err(|e| crate::commands::CommandError {
            message: format!("weather request failed: {e}"),
        })?
        .json()
        .map_err(|e| crate::commands::CommandError {
            message: format!("weather parse failed: {e}"),
        })?;
    let current = body.current.ok_or_else(|| crate::commands::CommandError {
        message: "weather response missing current conditions".into(),
    })?;
    let temp = current.temperature_2m.unwrap_or(0.0);
    let code = current.weather_code.unwrap_or(-1);
    Ok(WeatherSnapshot {
        temperature_f: temp,
        summary: weather_code_label(code).into(),
        wind_mph: current.wind_speed_10m,
        source: "Open-Meteo".into(),
    })
}
