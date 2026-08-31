//! On-device Gemma 4 E4B Instruct via a bundled llama-server sidecar.
//!
//! Ships the inference engine as a prebuilt llama.cpp binary (downloaded once into
//! the app Models folder) and loads Gemma 4 E4B Q4_0 weights locally. The server
//! exposes an OpenAI-compatible API on localhost — no Ollama or external LLM needed.

use crate::ai::openai_compat::{self, AiSettings};
use crate::ai::ChatMessage;
use anyhow::{anyhow, Context, Result};
use parking_lot::Mutex;
use serde::Serialize;
use std::io::{Read, Write};
use std::net::TcpListener;
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::Arc;
use std::time::Duration;
use tauri::{AppHandle, Emitter};

/// Bundled on-device LLM weights — Gemma 4 E4B Instruct, Q4_0 quantization.
pub const LLM_FILE_NAME: &str = "gemma-4-e4b-it-q4_0.gguf";
pub const LLM_DISPLAY_NAME: &str = "Gemma 4 E4B Instruct";
pub const LLM_MODEL_ID: &str = "gemma-4-e4b-it";
pub const LLM_DOWNLOAD_URL: &str =
    "https://huggingface.co/ggml-org/gemma-4-E4B-it-GGUF/resolve/main/gemma-4-E4B-it-Q4_0.gguf";
pub const LLM_MIN_BYTES: u64 = 4_000_000_000;

const SERVER_DIR: &str = "llama-server-b10621";

#[cfg(target_os = "windows")]
const SERVER_BIN: &str = "llama-server.exe";
#[cfg(not(target_os = "windows"))]
const SERVER_BIN: &str = "llama-server";

#[cfg(target_os = "windows")]
const SERVER_ARCHIVE_URL: &str =
    "https://github.com/ggml-org/llama.cpp/releases/download/b10621/llama-b10621-bin-win-cpu-x64.zip";
#[cfg(target_os = "macos")]
const SERVER_ARCHIVE_URL: &str =
    "https://github.com/ggml-org/llama.cpp/releases/download/b10621/llama-b10621-bin-macos-arm64.tar.gz";
#[cfg(all(not(target_os = "windows"), not(target_os = "macos")))]
const SERVER_ARCHIVE_URL: &str =
    "https://github.com/ggml-org/llama.cpp/releases/download/b10621/llama-b10621-bin-ubuntu-x64.tar.gz";

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LlmModelStatus {
    pub display_name: String,
    pub file_name: String,
    pub installed: bool,
    pub server_installed: bool,
    pub downloading: bool,
    pub download_progress: f32,
    pub bytes_downloaded: u64,
    pub bytes_total: Option<u64>,
    pub model_path: String,
    pub ready: bool,
    pub message: String,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
struct LlmDownloadProgressEvent {
    progress: f32,
    bytes_downloaded: u64,
    bytes_total: Option<u64>,
    done: bool,
    error: Option<String>,
}

/// Manages the on-device Gemma model file and llama-server sidecar process.
pub struct LocalLlm {
    models_dir: PathBuf,
    model_path: PathBuf,
    server_dir: PathBuf,
    server_bin: PathBuf,
    process: Mutex<Option<Child>>,
    port: Mutex<Option<u16>>,
    download_bytes: AtomicU64,
    download_total: AtomicU64,
    downloading: AtomicBool,
}

impl LocalLlm {
    pub fn new(models_dir: &Path) -> Self {
        let server_dir = models_dir.join(SERVER_DIR);
        let server_bin = server_dir.join(SERVER_BIN);
        Self {
            model_path: models_dir.join(LLM_FILE_NAME),
            models_dir: models_dir.to_path_buf(),
            server_dir,
            server_bin,
            process: Mutex::new(None),
            port: Mutex::new(None),
            download_bytes: AtomicU64::new(0),
            download_total: AtomicU64::new(0),
            downloading: AtomicBool::new(false),
        }
    }

    pub fn is_installed(&self) -> bool {
        self.model_path.is_file()
            && std::fs::metadata(&self.model_path)
                .map(|m| m.len() >= LLM_MIN_BYTES)
                .unwrap_or(false)
    }

    pub fn is_server_installed(&self) -> bool {
        self.server_bin.is_file()
    }

    pub fn is_downloading(&self) -> bool {
        self.downloading.load(Ordering::SeqCst)
    }

    pub fn is_loaded(&self) -> bool {
        self.port.lock().is_some()
    }

    pub fn status(&self) -> LlmModelStatus {
        let installed = self.is_installed();
        let server_installed = self.is_server_installed();
        let downloading = self.is_downloading();
        let ready = installed && server_installed && self.is_loaded();
        let bytes_downloaded = self.download_bytes.load(Ordering::SeqCst);
        let total_raw = self.download_total.load(Ordering::SeqCst);
        let bytes_total = if total_raw > 0 { Some(total_raw) } else { None };
        let download_progress = bytes_total
            .map(|t| (bytes_downloaded as f32 / t as f32).clamp(0.0, 1.0))
            .unwrap_or(0.0);

        let message = if ready {
            format!("{LLM_DISPLAY_NAME} running on-device (offline)")
        } else if downloading {
            format!("Downloading {LLM_DISPLAY_NAME} components…")
        } else if installed && server_installed {
            format!("{LLM_DISPLAY_NAME} ready — starts on first chat")
        } else if !server_installed {
            format!("Downloading inference engine, then {LLM_DISPLAY_NAME} (~4.3 GB total)")
        } else {
            format!("{LLM_DISPLAY_NAME} weights not installed (~4.3 GB)")
        };

        LlmModelStatus {
            display_name: LLM_DISPLAY_NAME.into(),
            file_name: LLM_FILE_NAME.into(),
            installed,
            server_installed,
            downloading,
            download_progress,
            bytes_downloaded,
            bytes_total,
            model_path: self.model_path.display().to_string(),
            ready,
            message,
        }
    }

    pub fn ensure_from_resources(&self, resource_models: Option<&Path>) -> Result<()> {
        if self.is_installed() {
            return Ok(());
        }
        let Some(resource_dir) = resource_models else {
            return Ok(());
        };
        let src = resource_dir.join(LLM_FILE_NAME);
        if !src.is_file() {
            return Ok(());
        }
        std::fs::create_dir_all(&self.models_dir)?;
        std::fs::copy(&src, &self.model_path)
            .with_context(|| format!("copy bundled LLM from {}", src.display()))?;
        tracing::info!(path = %self.model_path.display(), "Installed bundled LLM from app resources");
        Ok(())
    }

    pub async fn download_if_needed(self: &Arc<Self>, app: AppHandle) -> Result<()> {
        if self.is_installed() && self.is_server_installed() {
            return Ok(());
        }
        if self.downloading.swap(true, Ordering::SeqCst) {
            return Ok(());
        }

        let llm = Arc::clone(self);
        let app_dl = app.clone();
        let result = tokio::task::spawn_blocking(move || {
            if !llm.is_server_installed() {
                llm.download_server_blocking(&app_dl)?;
            }
            if !llm.is_installed() {
                llm.download_model_blocking(&app_dl)?;
            }
            Ok::<(), anyhow::Error>(())
        })
        .await;

        self.downloading.store(false, Ordering::SeqCst);

        match result {
            Ok(Ok(())) => {
                let _ = app.emit(
                    "ai:llm-download",
                    LlmDownloadProgressEvent {
                        progress: 1.0,
                        bytes_downloaded: self.download_bytes.load(Ordering::SeqCst),
                        bytes_total: {
                            let t = self.download_total.load(Ordering::SeqCst);
                            if t > 0 { Some(t) } else { None }
                        },
                        done: true,
                        error: None,
                    },
                );
                Ok(())
            }
            Ok(Err(e)) => {
                let msg = e.to_string();
                let _ = app.emit(
                    "ai:llm-download",
                    LlmDownloadProgressEvent {
                        progress: 0.0,
                        bytes_downloaded: 0,
                        bytes_total: None,
                        done: true,
                        error: Some(msg.clone()),
                    },
                );
                Err(anyhow!(msg))
            }
            Err(e) => Err(anyhow!("download task panicked: {e}")),
        }
    }

    fn emit_progress(&self, app: &AppHandle, progress: f32, downloaded: u64, total: Option<u64>) {
        let _ = app.emit(
            "ai:llm-download",
            LlmDownloadProgressEvent {
                progress,
                bytes_downloaded: downloaded,
                bytes_total: total,
                done: false,
                error: None,
            },
        );
    }

    fn download_server_blocking(&self, app: &AppHandle) -> Result<()> {
        tracing::info!(url = SERVER_ARCHIVE_URL, "Downloading llama-server sidecar");
        std::fs::create_dir_all(&self.server_dir)?;
        let client = reqwest::blocking::Client::builder()
            .user_agent("CollegeDesktop/0.1")
            .timeout(Duration::from_secs(3600))
            .build()
            .context("build HTTP client")?;

        let response = client
            .get(SERVER_ARCHIVE_URL)
            .send()
            .context("download llama-server archive")?
            .error_for_status()
            .context("llama-server archive HTTP error")?;

        let total = response.content_length();
        self.download_total.store(total.unwrap_or(0), Ordering::SeqCst);
        self.download_bytes.store(0, Ordering::SeqCst);

        let archive_path = self.server_dir.join("server-archive");
        let mut file = std::fs::File::create(&archive_path)?;
        let mut downloaded: u64 = 0;
        let mut reader = response;
        let mut buffer = [0u8; 64 * 1024];
        loop {
            let n = reader.read(&mut buffer)?;
            if n == 0 {
                break;
            }
            file.write_all(&buffer[..n])?;
            downloaded += n as u64;
            self.download_bytes.store(downloaded, Ordering::SeqCst);
            let progress = total
                .map(|t| downloaded as f32 / t as f32)
                .unwrap_or(0.0);
            self.emit_progress(app, progress, downloaded, total);
        }
        drop(file);

        self.extract_server_archive(&archive_path)?;
        let _ = std::fs::remove_file(&archive_path);

        if !self.is_server_installed() {
            return Err(anyhow!("llama-server binary not found after extraction"));
        }
        tracing::info!(path = %self.server_bin.display(), "llama-server sidecar ready");
        Ok(())
    }

    fn extract_server_archive(&self, archive_path: &Path) -> Result<()> {
        std::fs::create_dir_all(&self.server_dir)?;

        #[cfg(target_os = "windows")]
        {
            let file = std::fs::File::open(archive_path)?;
            let mut archive = zip::ZipArchive::new(file).context("open server zip")?;
            for i in 0..archive.len() {
                let mut entry = archive.by_index(i).context("read zip entry")?;
                let name = entry.name().to_string();
                let out = self.server_dir.join(&name);
                if name.ends_with('/') {
                    std::fs::create_dir_all(&out)?;
                    continue;
                }
                if let Some(parent) = out.parent() {
                    std::fs::create_dir_all(parent)?;
                }
                let mut out_file = std::fs::File::create(&out)?;
                std::io::copy(&mut entry, &mut out_file)?;
            }
        }

        #[cfg(not(target_os = "windows"))]
        {
            let status = Command::new("tar")
                .arg("-xzf")
                .arg(archive_path)
                .arg("-C")
                .arg(&self.server_dir)
                .status()
                .context("extract server tar.gz")?;
            if !status.success() {
                return Err(anyhow!("tar extraction failed"));
            }
        }

        if let Some(found) = find_file_recursive(&self.server_dir, SERVER_BIN) {
            if found != self.server_bin {
                std::fs::copy(&found, &self.server_bin)?;
            }
        }

        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            if self.server_bin.is_file() {
                let mut perms = std::fs::metadata(&self.server_bin)?.permissions();
                perms.set_mode(0o755);
                std::fs::set_permissions(&self.server_bin, perms)?;
            }
        }

        Ok(())
    }

    fn download_model_blocking(&self, app: &AppHandle) -> Result<()> {
        if self.is_installed() {
            return Ok(());
        }
        std::fs::create_dir_all(&self.models_dir)?;
        tracing::info!(url = LLM_DOWNLOAD_URL, "Downloading Gemma 4 E4B weights");

        let client = reqwest::blocking::Client::builder()
            .user_agent("CollegeDesktop/0.1")
            .timeout(Duration::from_secs(7200))
            .build()
            .context("build HTTP client")?;

        let response = client
            .get(LLM_DOWNLOAD_URL)
            .send()
            .context("start LLM download")?
            .error_for_status()
            .context("LLM download HTTP error")?;

        let total = response.content_length();
        self.download_total.store(total.unwrap_or(0), Ordering::SeqCst);
        self.download_bytes.store(0, Ordering::SeqCst);

        let tmp_path = self.model_path.with_extension("gguf.part");
        if tmp_path.exists() {
            let _ = std::fs::remove_file(&tmp_path);
        }

        let mut file = std::fs::File::create(&tmp_path)?;
        let mut downloaded: u64 = 0;
        let mut reader = response;
        let mut buffer = [0u8; 64 * 1024];
        loop {
            let n = reader.read(&mut buffer)?;
            if n == 0 {
                break;
            }
            file.write_all(&buffer[..n])?;
            downloaded += n as u64;
            self.download_bytes.store(downloaded, Ordering::SeqCst);
            let progress = total
                .map(|t| downloaded as f32 / t as f32)
                .unwrap_or(0.0);
            self.emit_progress(app, progress, downloaded, total);
        }
        drop(file);

        if downloaded < LLM_MIN_BYTES {
            let _ = std::fs::remove_file(&tmp_path);
            return Err(anyhow!(
                "Downloaded model too small ({downloaded} bytes)"
            ));
        }

        std::fs::rename(&tmp_path, &self.model_path)?;
        tracing::info!(path = %self.model_path.display(), bytes = downloaded, "Gemma weights ready");
        Ok(())
    }

    fn pick_port() -> Result<u16> {
        let listener = TcpListener::bind("127.0.0.1:0").context("bind ephemeral port")?;
        Ok(listener.local_addr()?.port())
    }

    fn health_check(port: u16) -> bool {
        let client = match reqwest::blocking::Client::builder()
            .timeout(Duration::from_secs(2))
            .build()
        {
            Ok(c) => c,
            Err(_) => return false,
        };
        let url = format!("http://127.0.0.1:{port}/health");
        client.get(&url).send().map(|r| r.status().is_success()).unwrap_or(false)
    }

    fn ensure_server_running(&self) -> Result<u16> {
        if let Some(port) = *self.port.lock() {
            if Self::health_check(port) {
                return Ok(port);
            }
        }

        if let Some(mut child) = self.process.lock().take() {
            let _ = child.kill();
        }

        if !self.is_server_installed() {
            return Err(anyhow!("llama-server not installed"));
        }
        if !self.is_installed() {
            return Err(anyhow!("{LLM_DISPLAY_NAME} weights not installed"));
        }

        let port = Self::pick_port()?;
        tracing::info!(port, path = %self.model_path.display(), "Starting llama-server");

        let mut cmd = Command::new(&self.server_bin);
        cmd.args([
            "-m",
            &self.model_path.to_string_lossy(),
            "--host",
            "127.0.0.1",
            "--port",
            &port.to_string(),
            "-c",
            "4096",
            "--parallel",
            "1",
            "--chat-template",
            "gemma",
        ]);
        #[cfg(target_os = "macos")]
        {
            cmd.arg("-ngl").arg("99");
        }

        let child = cmd
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn()
            .with_context(|| format!("spawn {}", self.server_bin.display()))?;

        *self.process.lock() = Some(child);

        for _ in 0..120 {
            if Self::health_check(port) {
                *self.port.lock() = Some(port);
                tracing::info!(port, "llama-server ready");
                return Ok(port);
            }
            std::thread::sleep(Duration::from_millis(500));
        }

        Err(anyhow!("llama-server failed to become healthy on port {port}"))
    }

    pub fn api_settings(&self) -> Result<AiSettings> {
        let port = self.ensure_server_running()?;
        Ok(AiSettings {
            base_url: format!("http://127.0.0.1:{port}/v1"),
            api_key: None,
            model: LLM_MODEL_ID.into(),
            onnx_model_path: None,
        })
    }

    pub async fn chat_stream<F>(
        self: &Arc<Self>,
        messages: &[ChatMessage],
        max_tokens: u32,
        on_chunk: F,
    ) -> Result<String>
    where
        F: FnMut(&str) + Send + 'static,
    {
        let llm = Arc::clone(self);
        let settings = tokio::task::spawn_blocking(move || llm.api_settings()).await??;
        openai_compat::chat_completion_stream(&settings, messages, max_tokens, on_chunk).await
    }

    pub async fn chat(self: &Arc<Self>, messages: &[ChatMessage], max_tokens: u32) -> Result<String> {
        let llm = Arc::clone(self);
        let settings = tokio::task::spawn_blocking(move || llm.api_settings()).await??;
        openai_compat::chat_completion(&settings, messages, max_tokens).await
    }
}

fn find_file_recursive(dir: &Path, name: &str) -> Option<PathBuf> {
    let entries = std::fs::read_dir(dir).ok()?;
    for entry in entries.flatten() {
        let path = entry.path();
        if path.file_name().and_then(|n| n.to_str()) == Some(name) && path.is_file() {
            return Some(path);
        }
        if path.is_dir() {
            if let Some(found) = find_file_recursive(&path, name) {
                return Some(found);
            }
        }
    }
    None
}

impl Drop for LocalLlm {
    fn drop(&mut self) {
        if let Some(mut child) = self.process.lock().take() {
            let _ = child.kill();
        }
    }
}
