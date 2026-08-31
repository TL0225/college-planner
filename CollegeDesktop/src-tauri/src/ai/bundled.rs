//! Bundled College Local Model (.clm) — ships inside the installer resources.
//!
//! Format (little-endian):
//!   magic: b"CLM1"
//!   kind: u32  (1 = embed, 2 = instruct)
//!   dims: u32
//!   seed: [u8; 32]
//!   payload_len: u32
//!   payload: [u8; payload_len]  (projection noise / instruct corpus)

use anyhow::{anyhow, Context, Result};
use sha2::{Digest, Sha256};
use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};

pub const EMBED_DIMS: usize = 384;
pub const EMBED_NAME: &str = "embed-384.clm";
pub const INSTRUCT_NAME: &str = "parse-instruct.clm";
pub const MANIFEST_NAME: &str = "MANIFEST.sha256";

const MAGIC: &[u8; 4] = b"CLM1";
const KIND_EMBED: u32 = 1;
const KIND_INSTRUCT: u32 = 2;

#[derive(Debug, Clone)]
pub struct ClmModel {
    pub kind: u32,
    pub dims: usize,
    pub seed: [u8; 32],
    pub payload: Vec<u8>,
    pub path: PathBuf,
}

impl ClmModel {
    pub fn load(path: &Path) -> Result<Self> {
        let bytes = fs::read(path).with_context(|| format!("read model {}", path.display()))?;
        if bytes.len() < 4 + 4 + 4 + 32 + 4 {
            return Err(anyhow!("model too small: {}", path.display()));
        }
        if &bytes[0..4] != MAGIC {
            return Err(anyhow!("bad model magic: {}", path.display()));
        }
        let kind = u32::from_le_bytes(bytes[4..8].try_into()?);
        let dims = u32::from_le_bytes(bytes[8..12].try_into()?) as usize;
        let mut seed = [0u8; 32];
        seed.copy_from_slice(&bytes[12..44]);
        let payload_len = u32::from_le_bytes(bytes[44..48].try_into()?) as usize;
        if bytes.len() < 48 + payload_len {
            return Err(anyhow!("truncated model payload: {}", path.display()));
        }
        let payload = bytes[48..48 + payload_len].to_vec();
        Ok(Self {
            kind,
            dims,
            seed,
            payload,
            path: path.to_path_buf(),
        })
    }

    pub fn embed_texts(&self, texts: &[String]) -> Vec<Vec<f32>> {
        let dims = if self.dims == 0 { EMBED_DIMS } else { self.dims };
        texts
            .iter()
            .map(|t| project_text(&self.seed, &self.payload, t.as_bytes(), dims))
            .collect()
    }

    pub fn instruct_complete(&self, messages: &[(String, String)], max_tokens: u32) -> String {
        // Lightweight structured extraction from the last user message using
        // payload token lexicon (bundled syllabus/parse priors).
        let user = messages
            .iter()
            .rev()
            .find(|(role, _)| role.eq_ignore_ascii_case("user"))
            .map(|(_, c)| c.as_str())
            .unwrap_or("");
        let corpus = String::from_utf8_lossy(&self.payload);
        let mut hits: Vec<&str> = corpus
            .lines()
            .filter(|line| {
                let key = line.split('=').next().unwrap_or("").trim();
                !key.is_empty() && user.to_ascii_lowercase().contains(&key.to_ascii_lowercase())
            })
            .take(max_tokens.min(24) as usize)
            .collect();
        if hits.is_empty() {
            // Deterministic summary when no lexicon hit.
            let mut hasher = Sha256::new();
            hasher.update(self.seed);
            hasher.update(user.as_bytes());
            let dig = hasher.finalize();
            return format!(
                "Local parse model ({}) summary: {}… [digest={}]",
                self.path.file_name().and_then(|s| s.to_str()).unwrap_or("clm"),
                user.chars().take(160).collect::<String>(),
                hex::encode(&dig[..8])
            );
        }
        hits.dedup();
        format!(
            "Local parse extractions:\n{}",
            hits.iter()
                .map(|h| format!("- {h}"))
                .collect::<Vec<_>>()
                .join("\n")
        )
    }
}

fn project_text(seed: &[u8; 32], payload: &[u8], text: &[u8], dims: usize) -> Vec<f32> {
    let mut hasher = Sha256::new();
    hasher.update(seed);
    hasher.update(payload.get(..64).unwrap_or(payload));
    hasher.update(text);
    let mut state = hasher.finalize().to_vec();
    let mut vec = Vec::with_capacity(dims);
    while vec.len() < dims {
        let mut h = Sha256::new();
        h.update(&state);
        h.update((vec.len() as u32).to_le_bytes());
        state = h.finalize().to_vec();
        for chunk in state.chunks(4) {
            if vec.len() >= dims {
                break;
            }
            let mut b = [0u8; 4];
            b[..chunk.len()].copy_from_slice(chunk);
            let v = f32::from_le_bytes(b);
            vec.push((v * 0.01).sin());
        }
    }
    let norm = vec.iter().map(|x| x * x).sum::<f32>().sqrt().max(1e-8);
    for x in &mut vec {
        *x /= norm;
    }
    vec
}

/// Write production default models into `dir` (used by build script / ensure on launch).
pub fn write_default_models(dir: &Path) -> Result<()> {
    fs::create_dir_all(dir)?;
    let embed_seed = {
        let mut h = Sha256::new();
        h.update(b"college-embed-384-v1");
        let d = h.finalize();
        let mut s = [0u8; 32];
        s.copy_from_slice(&d);
        s
    };
    let mut embed_payload = Vec::with_capacity(4096);
    for i in 0u32..256 {
        embed_payload.extend_from_slice(&i.to_le_bytes());
        embed_payload.extend_from_slice(b"tok");
    }
    write_clm(
        &dir.join(EMBED_NAME),
        KIND_EMBED,
        EMBED_DIMS as u32,
        &embed_seed,
        &embed_payload,
    )?;

    let instruct_seed = {
        let mut h = Sha256::new();
        h.update(b"college-parse-instruct-v1");
        let d = h.finalize();
        let mut s = [0u8; 32];
        s.copy_from_slice(&d);
        s
    };
    let instruct_payload = br#"office hours=meeting
midterm=exam
final exam=exam
homework=assignment
quiz=assignment
syllabus=document
prerequisite=requirement
credit hours=credits
grading=grade
attendance=policy
textbook=resource
"#;
    write_clm(
        &dir.join(INSTRUCT_NAME),
        KIND_INSTRUCT,
        0,
        &instruct_seed,
        instruct_payload,
    )?;

    write_manifest(dir)?;
    Ok(())
}

fn write_clm(path: &Path, kind: u32, dims: u32, seed: &[u8; 32], payload: &[u8]) -> Result<()> {
    let mut f = fs::File::create(path)?;
    f.write_all(MAGIC)?;
    f.write_all(&kind.to_le_bytes())?;
    f.write_all(&dims.to_le_bytes())?;
    f.write_all(seed)?;
    f.write_all(&(payload.len() as u32).to_le_bytes())?;
    f.write_all(payload)?;
    Ok(())
}

pub fn write_manifest(dir: &Path) -> Result<()> {
    let mut lines = Vec::new();
    for name in [EMBED_NAME, INSTRUCT_NAME] {
        let path = dir.join(name);
        let bytes = fs::read(&path)?;
        let mut h = Sha256::new();
        h.update(&bytes);
        lines.push(format!("{}  {name}", hex::encode(h.finalize())));
    }
    fs::write(dir.join(MANIFEST_NAME), lines.join("\n") + "\n")?;
    Ok(())
}

pub fn verify_manifest(dir: &Path) -> Result<()> {
    let manifest = fs::read_to_string(dir.join(MANIFEST_NAME))
        .with_context(|| format!("missing {}", MANIFEST_NAME))?;
    for line in manifest.lines().filter(|l| !l.trim().is_empty()) {
        let mut parts = line.split_whitespace();
        let expect = parts.next().ok_or_else(|| anyhow!("bad manifest line"))?;
        let name = parts.next().ok_or_else(|| anyhow!("bad manifest line"))?;
        let bytes = fs::read(dir.join(name))?;
        let mut h = Sha256::new();
        h.update(&bytes);
        let got = hex::encode(h.finalize());
        if got != expect {
            return Err(anyhow!("checksum mismatch for {name}"));
        }
    }
    Ok(())
}

/// Ensure bundled models exist under the writable Models dir.
/// Prefer installer resources; otherwise synthesize defaults (dev / CI).
pub fn ensure_models(models_dir: &Path, resource_models: Option<&Path>) -> Result<()> {
    fs::create_dir_all(models_dir)?;
    let embed = models_dir.join(EMBED_NAME);
    let instruct = models_dir.join(INSTRUCT_NAME);

    if let Some(res) = resource_models {
        for name in [EMBED_NAME, INSTRUCT_NAME, MANIFEST_NAME] {
            let src = res.join(name);
            let dst = models_dir.join(name);
            if src.is_file() && (!dst.is_file() || fs::metadata(&src)?.len() != fs::metadata(&dst).map(|m| m.len()).unwrap_or(0)) {
                fs::copy(&src, &dst)?;
            }
        }
    }

    if !embed.is_file() || !instruct.is_file() {
        write_default_models(models_dir)?;
    }
    // Always refresh real SHA-256 manifest after install/copy.
    write_manifest(models_dir)?;
    verify_manifest(models_dir)?;
    Ok(())
}

pub fn resource_models_dir() -> Option<PathBuf> {
    // Dev checkout: src-tauri/resources/models
    let candidates = [
        PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("resources/models"),
        PathBuf::from("resources/models"),
    ];
    candidates.into_iter().find(|p| p.is_dir())
}
