//! Credential store + biometric auth behind shared traits.
//! Windows: DPAPI + Windows Hello
//! macOS: Keychain + Touch ID / LocalAuthentication

pub mod traits;

#[cfg(target_os = "macos")]
mod keychain_macos;
#[cfg(target_os = "windows")]
mod dpapi_windows;

use crate::paths::AppPaths;
use anyhow::Result;
use parking_lot::Mutex;
use serde::Serialize;
use std::sync::Arc;
use traits::{BiometricAuthenticator, CredentialStore};

#[cfg(target_os = "macos")]
use keychain_macos::MacKeychainStore;
#[cfg(target_os = "windows")]
use dpapi_windows::WindowsCredentialStore;

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SecurityStatus {
    pub locked: bool,
    pub biometric_available: bool,
    pub platform: String,
}

pub struct SecurityService {
    store: Box<dyn CredentialStore>,
    biometrics: Box<dyn BiometricAuthenticator>,
    locked: Mutex<bool>,
}

impl SecurityService {
    pub fn new(paths: Arc<AppPaths>) -> Result<Self> {
        let store: Box<dyn CredentialStore> = {
            #[cfg(target_os = "macos")]
            {
                let _ = paths;
                Box::new(MacKeychainStore::new("com.college.app")?)
            }
            #[cfg(target_os = "windows")]
            {
                Box::new(WindowsCredentialStore::new(paths)?)
            }
            #[cfg(not(any(target_os = "macos", target_os = "windows")))]
            {
                Box::new(FileFallbackStore::new(paths)?)
            }
        };

        let biometrics: Box<dyn BiometricAuthenticator> = {
            #[cfg(target_os = "macos")]
            {
                Box::new(crate::platform::macos::MacLocalAuthBiometric::new())
            }
            #[cfg(target_os = "windows")]
            {
                Box::new(crate::platform::windows::WindowsHelloBiometric::new())
            }
            #[cfg(not(any(target_os = "macos", target_os = "windows")))]
            {
                Box::new(NoopBiometric)
            }
        };

        Ok(Self {
            store,
            biometrics,
            locked: Mutex::new(false),
        })
    }

    pub fn is_locked(&self) -> bool {
        *self.locked.lock()
    }

    pub fn lock(&self) {
        *self.locked.lock() = true;
    }

    pub fn unlock(&self, reason: &str) -> Result<bool> {
        if self.biometrics.is_available() {
            let ok = self.biometrics.authenticate(reason)?;
            if ok {
                *self.locked.lock() = false;
            }
            Ok(ok)
        } else {
            *self.locked.lock() = false;
            Ok(true)
        }
    }

    pub fn biometric_available(&self) -> bool {
        self.biometrics.is_available()
    }

    pub fn set_secret(&self, namespace: &str, key: &str, value: &[u8]) -> Result<()> {
        self.store.set(namespace, key, value)
    }

    pub fn get_secret(&self, namespace: &str, key: &str) -> Result<Option<Vec<u8>>> {
        self.store.get(namespace, key)
    }

    pub fn delete_secret(&self, namespace: &str, key: &str) -> Result<()> {
        self.store.delete(namespace, key)
    }

    pub fn status(&self) -> SecurityStatus {
        SecurityStatus {
            locked: self.is_locked(),
            biometric_available: self.biometric_available(),
            platform: std::env::consts::OS.to_string(),
        }
    }
}

#[cfg(not(any(target_os = "macos", target_os = "windows")))]
struct FileFallbackStore {
    root: std::path::PathBuf,
}

#[cfg(not(any(target_os = "macos", target_os = "windows")))]
impl FileFallbackStore {
    fn new(paths: Arc<AppPaths>) -> Result<Self> {
        let root = paths.root.join("secrets");
        std::fs::create_dir_all(&root)?;
        Ok(Self { root })
    }
}

#[cfg(not(any(target_os = "macos", target_os = "windows")))]
impl CredentialStore for FileFallbackStore {
    fn set(&self, namespace: &str, key: &str, value: &[u8]) -> Result<()> {
        let dir = self.root.join(namespace);
        std::fs::create_dir_all(&dir)?;
        std::fs::write(dir.join(key), value)?;
        Ok(())
    }

    fn get(&self, namespace: &str, key: &str) -> Result<Option<Vec<u8>>> {
        let path = self.root.join(namespace).join(key);
        if path.exists() {
            Ok(Some(std::fs::read(path)?))
        } else {
            Ok(None)
        }
    }

    fn delete(&self, namespace: &str, key: &str) -> Result<()> {
        let path = self.root.join(namespace).join(key);
        if path.exists() {
            std::fs::remove_file(path)?;
        }
        Ok(())
    }
}

#[cfg(not(any(target_os = "macos", target_os = "windows")))]
struct NoopBiometric;

#[cfg(not(any(target_os = "macos", target_os = "windows")))]
impl BiometricAuthenticator for NoopBiometric {
    fn is_available(&self) -> bool {
        false
    }

    fn authenticate(&self, _reason: &str) -> Result<bool> {
        Ok(true)
    }
}
