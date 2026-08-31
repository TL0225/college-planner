//! WinUI 3 XAML Islands capability status (InkCanvas / MediaPlayerElement).

use serde::Serialize;

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct InkingCapability {
    pub xaml_islands_available: bool,
    pub ink_canvas_supported: bool,
    pub media_player_supported: bool,
    pub message: String,
}

pub fn capability() -> InkingCapability {
    let wasdk = std::path::Path::new(r"C:\Program Files\WindowsApps")
        .exists()
        && (std::path::Path::new(r"C:\Windows\System32\Microsoft.UI.Xaml.dll").exists()
            || std::path::Path::new(r"C:\Windows\System32\WinUI3.dll").exists());

    InkingCapability {
        xaml_islands_available: wasdk,
        ink_canvas_supported: wasdk,
        media_player_supported: wasdk,
        message: if wasdk {
            "WinUI 3 runtime detected. XAML Islands can host InkCanvas and MediaPlayerElement."
                .into()
        } else {
            "WinUI 3 runtime not detected. Digital inking uses web canvas fallback.".into()
        },
    }
}
