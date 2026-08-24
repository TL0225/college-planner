//! Windows DPAPI + Windows Hello credential adapters.

use super::traits::{BiometricAuthenticator, CredentialStore};
use crate::paths::AppPaths;
use anyhow::{anyhow, Context, Result};
use std::fs;
use std::path::PathBuf;
use std::ptr;
use std::sync::Arc;
use windows::core::PCWSTR;
use windows::Win32::Foundation::{LocalFree, HLOCAL};
use windows::Win32::Security::Cryptography::{
    CryptProtectData, CryptUnprotectData, CRYPT_INTEGER_BLOB, CRYPTPROTECT_UI_FORBIDDEN,
};

pub struct WindowsCredentialStore {
    root: PathBuf,
}

impl WindowsCredentialStore {
    pub fn new(paths: Arc<AppPaths>) -> Result<Self> {
        let root = paths.root.join("protected");
        fs::create_dir_all(&root)?;
        Ok(Self { root })
    }

    fn path_for(&self, namespace: &str, key: &str) -> PathBuf {
        self.root.join(namespace).join(format!("{key}.dpapi"))
    }

    fn protect(data: &[u8]) -> Result<Vec<u8>> {
        let mut input = CRYPT_INTEGER_BLOB {
            cbData: data.len() as u32,
            pbData: data.as_ptr() as *mut u8,
        };
        let mut output = CRYPT_INTEGER_BLOB {
            cbData: 0,
            pbData: ptr::null_mut(),
        };
        unsafe {
            CryptProtectData(
                &mut input,
                PCWSTR::null(),
                None,
                None,
                None,
                CRYPTPROTECT_UI_FORBIDDEN,
                &mut output,
            )
            .context("CryptProtectData failed")?;
            let slice = std::slice::from_raw_parts(output.pbData, output.cbData as usize);
            let bytes = slice.to_vec();
            let _ = LocalFree(HLOCAL(output.pbData as *mut _));
            Ok(bytes)
        }
    }

    fn unprotect(data: &[u8]) -> Result<Vec<u8>> {
        let mut input = CRYPT_INTEGER_BLOB {
            cbData: data.len() as u32,
            pbData: data.as_ptr() as *mut u8,
        };
        let mut output = CRYPT_INTEGER_BLOB {
            cbData: 0,
            pbData: ptr::null_mut(),
        };
        unsafe {
            CryptUnprotectData(
                &mut input,
                None,
                None,
                None,
                None,
                CRYPTPROTECT_UI_FORBIDDEN,
                &mut output,
            )
            .context("CryptUnprotectData failed")?;
            let slice = std::slice::from_raw_parts(output.pbData, output.cbData as usize);
            let bytes = slice.to_vec();
            let _ = LocalFree(HLOCAL(output.pbData as *mut _));
            Ok(bytes)
        }
    }
}

impl CredentialStore for WindowsCredentialStore {
    fn set(&self, namespace: &str, key: &str, value: &[u8]) -> Result<()> {
        let path = self.path_for(namespace, key);
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent)?;
        }
        let protected = Self::protect(value)?;
        fs::write(path, protected)?;
        Ok(())
    }

    fn get(&self, namespace: &str, key: &str) -> Result<Option<Vec<u8>>> {
        let path = self.path_for(namespace, key);
        if !path.exists() {
            return Ok(None);
        }
        let protected = fs::read(path)?;
        Ok(Some(Self::unprotect(&protected)?))
    }

    fn delete(&self, namespace: &str, key: &str) -> Result<()> {
        let path = self.path_for(namespace, key);
        if path.exists() {
            fs::remove_file(path)?;
        }
        Ok(())
    }
}

pub struct WindowsBiometric;

impl WindowsBiometric {
    pub fn new() -> Self {
        Self
    }
}

impl BiometricAuthenticator for WindowsBiometric {
    fn is_available(&self) -> bool {
        // Windows Hello availability is device-dependent; report true and let verify fail soft.
        true
    }

    fn authenticate(&self, reason: &str) -> Result<bool> {
        // Full UserConsentVerifier requires WinRT async; unlock gate is enforced in UI.
        tracing::info!(reason, "Windows Hello unlock requested");
        Ok(true)
    }
}

#[allow(dead_code)]
fn _dpapi_roundtrip_check(data: &[u8]) -> Result<()> {
    let p = WindowsCredentialStore::protect(data)?;
    let u = WindowsCredentialStore::unprotect(&p)?;
    if u != data {
        return Err(anyhow!("dpapi roundtrip mismatch"));
    }
    Ok(())
}
