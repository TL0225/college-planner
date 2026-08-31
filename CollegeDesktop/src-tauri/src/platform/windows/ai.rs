//! DirectML, Copilot+ NPU, and ONNX runtime capability detection.

use serde::Serialize;

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AiHardwareProfile {
    pub backend: String,
    pub directml_available: bool,
    pub copilot_npu_available: bool,
    pub npu_model: Option<String>,
}

pub fn device_label() -> &'static str {
    if copilot_npu_available() {
        "copilot-npu"
    } else if directml_available() {
        "directml"
    } else {
        "cpu"
    }
}

pub fn directml_available() -> bool {
    std::path::Path::new(r"C:\Windows\System32\DirectML.dll").exists()
        || std::path::Path::new(r"C:\Windows\System32\directml.dll").exists()
}

/// Copilot+ PCs ship Windows AI runtime with Phi-Silica on NPU (Windows 11 24H2+).
pub fn copilot_npu_available() -> bool {
    std::path::Path::new(r"C:\Windows\System32\Windows.AI.MachineLearning.dll").exists()
        || std::path::Path::new(r"C:\Windows\System32\PhiSilica.dll").exists()
}

pub fn profile() -> AiHardwareProfile {
    let copilot = copilot_npu_available();
    AiHardwareProfile {
        backend: device_label().to_string(),
        directml_available: directml_available(),
        copilot_npu_available: copilot,
        npu_model: if copilot {
            Some("Phi-Silica".into())
        } else {
            None
        },
    }
}
