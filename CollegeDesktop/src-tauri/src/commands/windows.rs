//! Windows platform IPC commands.

use crate::commands::CmdResult;
use serde::{Deserialize, Serialize};
use tauri::{AppHandle, WebviewWindow};

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct WindowsCapabilities {
    pub os: String,
    pub dwm_mica: bool,
    pub taskbar_progress: bool,
    pub uri_protocol: bool,
    pub widgets_board: bool,
    pub focus_sessions: bool,
    pub directml: bool,
    pub copilot_npu: bool,
    pub xaml_islands: bool,
    pub dpapi: bool,
    pub eco_qos: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct WindowsPersonalization {
    pub accent_color: Option<String>,
    pub text_scale_percent: u32,
    pub high_contrast: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AiHardwareProfile {
    pub backend: String,
    pub directml_available: bool,
    pub copilot_npu_available: bool,
    pub npu_model: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct FocusSessionStatus {
    pub supported: bool,
    pub active: bool,
    pub message: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct WidgetFeed {
    pub id: String,
    pub title: String,
    pub template: String,
    pub data: serde_json::Value,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct WidgetsStatus {
    pub provider_registered: bool,
    pub feeds: Vec<WidgetFeed>,
    pub feed_export_path: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SearchIndexEntry {
    pub id: String,
    pub title: String,
    pub path: String,
    pub category: Option<String>,
    pub updated_at: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SearchIndexStatus {
    pub indexed_paths: usize,
    pub catalog_file: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct InkingCapability {
    pub xaml_islands_available: bool,
    pub ink_canvas_supported: bool,
    pub media_player_supported: bool,
    pub message: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TaskbarProgressInput {
    pub completed: u64,
    pub total: u64,
    pub state: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct WidgetFeedsInput {
    pub agenda: Option<serde_json::Value>,
    pub gpa: Option<serde_json::Value>,
    pub pipeline: Option<serde_json::Value>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CopyRichTextInput {
    pub plain: String,
    pub html: Option<String>,
}

#[tauri::command]
pub fn windows_get_capabilities() -> WindowsCapabilities {
    #[cfg(target_os = "windows")]
    {
        let ai_profile = crate::platform::windows::ai::profile();
        let ink = crate::platform::windows::inking::capability();
        WindowsCapabilities {
            os: "windows".into(),
            dwm_mica: true,
            taskbar_progress: true,
            uri_protocol: true,
            widgets_board: true,
            focus_sessions: true,
            directml: ai_profile.directml_available,
            copilot_npu: ai_profile.copilot_npu_available,
            xaml_islands: ink.xaml_islands_available,
            dpapi: true,
            eco_qos: true,
        }
    }
    #[cfg(not(target_os = "windows"))]
    {
        WindowsCapabilities {
            os: std::env::consts::OS.into(),
            dwm_mica: false,
            taskbar_progress: false,
            uri_protocol: false,
            widgets_board: false,
            focus_sessions: false,
            directml: false,
            copilot_npu: false,
            xaml_islands: false,
            dpapi: false,
            eco_qos: false,
        }
    }
}

#[tauri::command]
pub fn windows_sync_theme(window: WebviewWindow, dark: bool) -> CmdResult<()> {
    #[cfg(target_os = "windows")]
    {
        crate::platform::windows::window_chrome::sync_theme(&window, dark)?;
    }
    let _ = (window, dark);
    Ok(())
}

#[tauri::command]
pub fn windows_set_taskbar_progress(
    window: WebviewWindow,
    input: TaskbarProgressInput,
) -> CmdResult<()> {
    #[cfg(target_os = "windows")]
    {
        use crate::platform::windows::taskbar::{self, TaskbarProgressState};
        let state = match input.state.as_str() {
            "indeterminate" => TaskbarProgressState::Indeterminate,
            "error" => TaskbarProgressState::Error,
            "paused" => TaskbarProgressState::Paused,
            "normal" => TaskbarProgressState::Normal,
            _ => TaskbarProgressState::None,
        };
        taskbar::set_progress(&window, input.completed, input.total, state)?;
    }
    let _ = (window, input);
    Ok(())
}

#[tauri::command]
pub fn windows_clear_taskbar_progress(window: WebviewWindow) -> CmdResult<()> {
    #[cfg(target_os = "windows")]
    {
        crate::platform::windows::taskbar::clear_progress(&window)?;
    }
    let _ = window;
    Ok(())
}

#[tauri::command]
pub fn windows_get_personalization() -> CmdResult<WindowsPersonalization> {
    #[cfg(target_os = "windows")]
    {
        let p = crate::platform::windows::personalization::read_personalization();
        return Ok(WindowsPersonalization {
            accent_color: p.accent_color,
            text_scale_percent: p.text_scale_percent,
            high_contrast: p.high_contrast,
        });
    }
    #[cfg(not(target_os = "windows"))]
    {
        Err(crate::commands::CommandError {
            message: "Windows personalization is only available on Windows".into(),
        })
    }
}

#[tauri::command]
pub fn windows_get_ai_profile() -> CmdResult<AiHardwareProfile> {
    #[cfg(target_os = "windows")]
    {
        let p = crate::platform::windows::ai::profile();
        return Ok(AiHardwareProfile {
            backend: p.backend,
            directml_available: p.directml_available,
            copilot_npu_available: p.copilot_npu_available,
            npu_model: p.npu_model,
        });
    }
    #[cfg(not(target_os = "windows"))]
    {
        Err(crate::commands::CommandError {
            message: "Windows AI profile is only available on Windows".into(),
        })
    }
}

#[tauri::command]
pub fn windows_start_focus_session(duration_minutes: u32) -> CmdResult<FocusSessionStatus> {
    #[cfg(target_os = "windows")]
    {
        let s = crate::platform::windows::focus::start_focus_session(duration_minutes);
        return Ok(FocusSessionStatus {
            supported: s.supported,
            active: s.active,
            message: s.message,
        });
    }
    #[cfg(not(target_os = "windows"))]
    {
        let _ = duration_minutes;
        Err(crate::commands::CommandError {
            message: "Focus sessions are only available on Windows".into(),
        })
    }
}

#[tauri::command]
pub fn windows_end_focus_session() -> CmdResult<FocusSessionStatus> {
    #[cfg(target_os = "windows")]
    {
        let s = crate::platform::windows::focus::end_focus_session();
        return Ok(FocusSessionStatus {
            supported: s.supported,
            active: s.active,
            message: s.message,
        });
    }
    #[cfg(not(target_os = "windows"))]
    {
        Err(crate::commands::CommandError {
            message: "Focus sessions are only available on Windows".into(),
        })
    }
}

#[tauri::command]
pub fn windows_get_focus_status() -> CmdResult<FocusSessionStatus> {
    #[cfg(target_os = "windows")]
    {
        let s = crate::platform::windows::focus::status();
        return Ok(FocusSessionStatus {
            supported: s.supported,
            active: s.active,
            message: s.message,
        });
    }
    #[cfg(not(target_os = "windows"))]
    {
        Err(crate::commands::CommandError {
            message: "Focus sessions are only available on Windows".into(),
        })
    }
}

#[tauri::command]
pub fn windows_build_widget_feeds(
    state: tauri::State<'_, crate::AppState>,
    input: WidgetFeedsInput,
) -> CmdResult<WidgetsStatus> {
    #[cfg(target_os = "windows")]
    {
        let s = crate::platform::windows::widgets::build_widget_feeds(
            &state.paths.root,
            input.agenda,
            input.gpa,
            input.pipeline,
        );
        return Ok(WidgetsStatus {
            provider_registered: s.provider_registered,
            feed_export_path: s.feed_export_path,
            feeds: s
                .feeds
                .into_iter()
                .map(|f| WidgetFeed {
                    id: f.id,
                    title: f.title,
                    template: f.template,
                    data: f.data,
                })
                .collect(),
        });
    }
    #[cfg(not(target_os = "windows"))]
    {
        let _ = input;
        Err(crate::commands::CommandError {
            message: "Widgets are only available on Windows".into(),
        })
    }
}

#[tauri::command]
pub fn windows_sync_search_index(
    state: tauri::State<'_, crate::AppState>,
    entries: Vec<SearchIndexEntry>,
) -> CmdResult<SearchIndexStatus> {
    #[cfg(target_os = "windows")]
    {
        use crate::platform::windows::search;
        let vault = state.paths.root.join("vault");
        let mapped: Vec<search::SearchIndexEntry> = entries
            .into_iter()
            .map(|e| search::SearchIndexEntry {
                id: e.id,
                title: e.title,
                path: e.path,
                category: e.category,
                updated_at: e.updated_at,
            })
            .collect();
        let s = search::sync_vault_catalog(&vault, &mapped)?;
        return Ok(SearchIndexStatus {
            indexed_paths: s.indexed_paths,
            catalog_file: s.catalog_file,
        });
    }
    #[cfg(not(target_os = "windows"))]
    {
        let _ = (state, entries);
        Err(crate::commands::CommandError {
            message: "Search index sync is only available on Windows".into(),
        })
    }
}

#[tauri::command]
pub fn windows_share_file(path: String) -> CmdResult<()> {
    #[cfg(target_os = "windows")]
    {
        crate::platform::windows::share::share_file(std::path::Path::new(&path))?;
        return Ok(());
    }
    #[cfg(not(target_os = "windows"))]
    {
        let _ = path;
        Err(crate::commands::CommandError {
            message: "Windows share is only available on Windows".into(),
        })
    }
}

#[tauri::command]
pub fn windows_copy_rich_text(input: CopyRichTextInput) -> CmdResult<()> {
    #[cfg(target_os = "windows")]
    {
        crate::platform::windows::share::copy_rich_text(&input.plain, input.html.as_deref())?;
        return Ok(());
    }
    #[cfg(not(target_os = "windows"))]
    {
        let _ = input;
        Err(crate::commands::CommandError {
            message: "Windows clipboard is only available on Windows".into(),
        })
    }
}

#[tauri::command]
pub fn windows_get_inking_capability() -> CmdResult<InkingCapability> {
    #[cfg(target_os = "windows")]
    {
        let c = crate::platform::windows::inking::capability();
        return Ok(InkingCapability {
            xaml_islands_available: c.xaml_islands_available,
            ink_canvas_supported: c.ink_canvas_supported,
            media_player_supported: c.media_player_supported,
            message: c.message,
        });
    }
    #[cfg(not(target_os = "windows"))]
    {
        Err(crate::commands::CommandError {
            message: "Inking capability is only available on Windows".into(),
        })
    }
}

#[tauri::command]
pub fn windows_set_efficiency_mode(enabled: bool) -> CmdResult<()> {
    #[cfg(target_os = "windows")]
    {
        crate::platform::windows::power::enable_efficiency_mode(enabled)?;
    }
    let _ = enabled;
    Ok(())
}

#[tauri::command]
pub fn windows_battery_saver_active() -> bool {
    #[cfg(target_os = "windows")]
    {
        return crate::platform::windows::power::battery_saver_active();
    }
    #[cfg(not(target_os = "windows"))]
    {
        false
    }
}

#[tauri::command]
pub fn windows_refresh_shell_integration(_app: AppHandle) -> CmdResult<()> {
    #[cfg(target_os = "windows")]
    {
        crate::platform::windows::shell::register_uri_protocol()?;
        crate::platform::windows::shell::refresh_jump_list()?;
    }
    Ok(())
}

#[tauri::command]
pub fn windows_mmap_file_size(path: String) -> CmdResult<usize> {
    #[cfg(target_os = "windows")]
    {
        let mapped = crate::platform::windows::mmap::mmap_read_only(std::path::Path::new(&path))?;
        return Ok(mapped.len());
    }
    #[cfg(not(target_os = "windows"))]
    {
        let _ = path;
        Err(crate::commands::CommandError {
            message: "mmap is only available on Windows".into(),
        })
    }
}
