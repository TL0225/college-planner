//! macOS 26 Tahoe — MLX / Core ML device labeling for bundled local models.

pub fn device_label() -> &'static str {
    if cfg!(target_arch = "aarch64") {
        "mlx"
    } else {
        "coreml"
    }
}
