use crate::commands::CmdResult;
use crate::AppState;
use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};
use std::process::Command;
use std::io::Cursor;
use tauri::State;

#[cfg(target_os = "windows")]
const TYPST_BIN_NAME: &str = "typst.exe";
#[cfg(not(target_os = "windows"))]
const TYPST_BIN_NAME: &str = "typst";

fn resource_typst_dirs() -> Vec<PathBuf> {
    [
        PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("resources/typst"),
        PathBuf::from("resources/typst"),
    ]
    .into_iter()
    .filter(|p| p.is_dir())
    .collect()
}

fn typst_binary_runs(path: &Path) -> bool {
    Command::new(path)
        .arg("--version")
        .output()
        .map(|o| o.status.success())
        .unwrap_or(false)
}

/// Resolve the Typst CLI: `TYPST_PATH` env, bundled `resources/typst`, then PATH.
pub fn resolve_typst_binary() -> Option<PathBuf> {
    if let Ok(path) = std::env::var("TYPST_PATH") {
        let candidate = PathBuf::from(path);
        if candidate.is_file() && typst_binary_runs(&candidate) {
            return Some(candidate);
        }
    }

    for dir in resource_typst_dirs() {
        for name in [TYPST_BIN_NAME, "typst"] {
            let candidate = dir.join(name);
            if candidate.is_file() && typst_binary_runs(&candidate) {
                return Some(candidate);
            }
        }
    }

    if typst_binary_runs(Path::new("typst")) {
        return Some(PathBuf::from("typst"));
    }

    None
}

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

/// Whether the Typst CLI is available (resume PDF export).
#[tauri::command]
pub fn platform_typst_available() -> bool {
    resolve_typst_binary().is_some()
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct TypstInstallResult {
    pub installed: bool,
    pub path: Option<String>,
    pub message: String,
}

fn typst_install_dir() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("resources/typst")
}

fn typst_release_asset_name() -> Option<&'static str> {
    #[cfg(all(target_os = "windows", target_arch = "x86_64"))]
    {
        return Some("typst-x86_64-pc-windows-msvc.zip");
    }
    #[cfg(all(target_os = "macos", target_arch = "aarch64"))]
    {
        return Some("typst-aarch64-apple-darwin.tar.xz");
    }
    #[cfg(all(target_os = "macos", target_arch = "x86_64"))]
    {
        return Some("typst-x86_64-apple-darwin.tar.xz");
    }
    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    {
        return Some("typst-x86_64-unknown-linux-musl.tar.xz");
    }
    #[cfg(not(any(
        all(target_os = "windows", target_arch = "x86_64"),
        all(target_os = "macos", target_arch = "aarch64"),
        all(target_os = "macos", target_arch = "x86_64"),
        all(target_os = "linux", target_arch = "x86_64"),
    )))]
    {
        None
    }
}

#[derive(Debug, Deserialize)]
struct GithubRelease {
    assets: Vec<GithubAsset>,
}

#[derive(Debug, Deserialize)]
struct GithubAsset {
    name: String,
    browser_download_url: String,
}

/// Download Typst CLI from GitHub releases into `resources/typst/` when missing.
#[tauri::command]
pub async fn platform_typst_ensure_download() -> CmdResult<TypstInstallResult> {
    if let Some(path) = resolve_typst_binary() {
        return Ok(TypstInstallResult {
            installed: true,
            path: Some(path.display().to_string()),
            message: "Typst is already available".into(),
        });
    }

    let asset_name = typst_release_asset_name().ok_or_else(|| crate::commands::CommandError {
        message: "Automatic Typst download is not supported on this platform".into(),
    })?;

    let client = reqwest::Client::builder()
        .user_agent("CollegeDesktop/0.1")
        .timeout(std::time::Duration::from_secs(120))
        .build()
        .map_err(|e| crate::commands::CommandError {
            message: e.to_string(),
        })?;

    let release: GithubRelease = client
        .get("https://api.github.com/repos/typst/typst/releases/latest")
        .send()
        .await
        .map_err(|e| crate::commands::CommandError {
            message: format!("Typst release lookup failed: {e}"),
        })?
        .json()
        .await
        .map_err(|e| crate::commands::CommandError {
            message: format!("Typst release parse failed: {e}"),
        })?;

    let asset = release
        .assets
        .into_iter()
        .find(|a| a.name == asset_name)
        .ok_or_else(|| crate::commands::CommandError {
            message: format!("Typst release missing asset {asset_name}"),
        })?;

    let bytes = client
        .get(&asset.browser_download_url)
        .send()
        .await
        .map_err(|e| crate::commands::CommandError {
            message: format!("Typst download failed: {e}"),
        })?
        .bytes()
        .await
        .map_err(|e| crate::commands::CommandError {
            message: format!("Typst download read failed: {e}"),
        })?;

    let install_dir = typst_install_dir();
    std::fs::create_dir_all(&install_dir).map_err(|e| crate::commands::CommandError {
        message: format!("Could not create Typst install dir: {e}"),
    })?;

    if asset_name.ends_with(".zip") {
        let reader = std::io::Cursor::new(bytes);
        let mut archive =
            zip::ZipArchive::new(reader).map_err(|e| crate::commands::CommandError {
                message: format!("Typst zip extract failed: {e}"),
            })?;
        for i in 0..archive.len() {
            let mut file = archive.by_index(i).map_err(|e| crate::commands::CommandError {
                message: format!("Typst zip entry failed: {e}"),
            })?;
            let outpath = match file.enclosed_name() {
                Some(path) => install_dir.join(path),
                None => continue,
            };
            if file.name().ends_with('/') {
                std::fs::create_dir_all(&outpath).ok();
                continue;
            }
            if let Some(parent) = outpath.parent() {
                std::fs::create_dir_all(parent).ok();
            }
            let mut outfile = std::fs::File::create(&outpath).map_err(|e| {
                crate::commands::CommandError {
                    message: format!("Typst write failed: {e}"),
                }
            })?;
            std::io::copy(&mut file, &mut outfile).map_err(|e| crate::commands::CommandError {
                message: format!("Typst extract copy failed: {e}"),
            })?;
        }
    } else {
        return Err(crate::commands::CommandError {
            message: format!(
                "Downloaded {asset_name} — extract manually to {}",
                install_dir.display()
            ),
        });
    }

    let installed = resolve_typst_binary().ok_or_else(|| crate::commands::CommandError {
        message: "Typst downloaded but binary not found after extract".into(),
    })?;

    Ok(TypstInstallResult {
        installed: true,
        path: Some(installed.display().to_string()),
        message: "Typst installed to resources/typst".into(),
    })
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

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ApproxLocation {
    pub lat: f64,
    pub lon: f64,
    pub label: String,
    pub source: String,
}

#[derive(Debug, Deserialize)]
struct IpApiGeo {
    #[serde(default)]
    status: String,
    lat: Option<f64>,
    lon: Option<f64>,
    city: Option<String>,
    #[serde(rename = "regionName")]
    region_name: Option<String>,
    country: Option<String>,
}

/// Approximate location for weather without WebView geolocation prompts.
/// Uses ip-api.com (HTTP); falls back to a US default if unavailable.
#[tauri::command]
pub fn platform_approx_location() -> CmdResult<ApproxLocation> {
    let client = reqwest::blocking::Client::builder()
        .timeout(std::time::Duration::from_secs(6))
        .build()
        .map_err(|e| crate::commands::CommandError {
            message: e.to_string(),
        })?;
    if let Ok(resp) = client
        .get("http://ip-api.com/json/?fields=status,message,lat,lon,city,regionName,country")
        .send()
    {
        if let Ok(body) = resp.json::<IpApiGeo>() {
            if body.status.eq_ignore_ascii_case("success") {
                if let (Some(lat), Some(lon)) = (body.lat, body.lon) {
                    let label = [body.city, body.region_name, body.country]
                        .into_iter()
                        .flatten()
                        .filter(|s| !s.trim().is_empty())
                        .collect::<Vec<_>>()
                        .join(", ");
                    return Ok(ApproxLocation {
                        lat,
                        lon,
                        label: if label.is_empty() {
                            "Approximate location".into()
                        } else {
                            label
                        },
                        source: "ip-approx".into(),
                    });
                }
            }
        }
    }
    Ok(ApproxLocation {
        lat: 40.7128,
        lon: -74.006,
        label: "New York, NY (default)".into(),
        source: "default".into(),
    })
}
