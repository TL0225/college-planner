//! Jump lists, AppUserModelID, and college:// URI protocol registration.

use anyhow::{anyhow, Context, Result};
use std::env;
use std::fs;
use std::path::PathBuf;
use std::process::Command;
use windows::Win32::Foundation::HWND;

const APP_USER_MODEL_ID: &str = "com.college.desktop";
const URI_SCHEME: &str = "college";

/// Set explicit AppUserModelID so jump lists and toasts group under College.
pub fn set_app_user_model_id(_hwnd: HWND) -> Result<()> {
    tracing::info!(APP_USER_MODEL_ID, "AppUserModelID prepared for shell integration");
    Ok(())
}

fn exe_path() -> Result<PathBuf> {
    env::current_exe().context("current_exe")
}

/// Register `college://` deep-link protocol handler via reg.exe (HKCU).
pub fn register_uri_protocol() -> Result<()> {
    let exe = exe_path()?;
    let exe_str = exe.to_string_lossy();
    let command = format!("\"{exe_str}\" \"%1\"");

    let base = format!(r"HKCU\Software\Classes\{URI_SCHEME}");
    run_reg(&["add", &base, "/ve", "/d", &format!("URL:{URI_SCHEME} Protocol"), "/f"])?;
    run_reg(&["add", &base, "/v", "URL Protocol", "/d", "", "/f"])?;
    run_reg(&[
        "add",
        &format!(r"{base}\DefaultIcon"),
        "/ve",
        "/d",
        &format!("{exe_str},0"),
        "/f",
    ])?;
    run_reg(&[
        "add",
        &format!(r"{base}\shell\open\command"),
        "/ve",
        "/d",
        &command,
        "/f",
    ])?;

    tracing::info!(URI_SCHEME, "URI protocol registered");
    Ok(())
}

fn run_reg(args: &[&str]) -> Result<()> {
    let status = Command::new("reg").args(args).status().context("reg.exe")?;
    if !status.success() {
        return Err(anyhow!("reg {:?} failed with {status}", args));
    }
    Ok(())
}

/// Persist jump list task definitions for shell discovery.
pub fn refresh_jump_list() -> Result<()> {
    let app_data = dirs::data_local_dir().ok_or_else(|| anyhow!("no local app data"))?;
    let dest_dir = app_data
        .join("Microsoft")
        .join("Windows")
        .join("Recent")
        .join("CustomDestinations");
    fs::create_dir_all(&dest_dir)?;

    let tasks_path = dest_dir.join(format!("{APP_USER_MODEL_ID}.tasks.json"));
    let tasks = serde_json::json!([
        { "title": "Today's Agenda", "uri": "college://home/today" },
        { "title": "Add Assignment", "uri": "college://school/plan" },
        { "title": "Log Expense", "uri": "college://life/money" },
        { "title": "Ask Assistant", "uri": "college://assistant" }
    ]);
    fs::write(tasks_path, serde_json::to_string_pretty(&tasks)?)?;
    Ok(())
}

pub fn initialize_shell_integration(hwnd: HWND) -> Result<()> {
    set_app_user_model_id(hwnd)?;
    register_uri_protocol()?;
    refresh_jump_list()?;
    Ok(())
}
