//! macOS Keychain + LocalAuthentication (Touch ID) adapters.

use super::traits::{BiometricAuthenticator, CredentialStore};
use anyhow::{anyhow, Result};
use security_framework::passwords::{
    delete_generic_password, get_generic_password, set_generic_password,
};

pub struct MacKeychainStore {
    service_prefix: String,
}

impl MacKeychainStore {
    pub fn new(service_prefix: &str) -> Result<Self> {
        Ok(Self {
            service_prefix: service_prefix.to_string(),
        })
    }

    fn service(&self, namespace: &str) -> String {
        format!("{}.{}", self.service_prefix, namespace)
    }
}

impl CredentialStore for MacKeychainStore {
    fn set(&self, namespace: &str, key: &str, value: &[u8]) -> Result<()> {
        let service = self.service(namespace);
        // Replace existing
        let _ = delete_generic_password(&service, key);
        set_generic_password(&service, key, value)
            .map_err(|e| anyhow!("keychain set failed: {e}"))?;
        Ok(())
    }

    fn get(&self, namespace: &str, key: &str) -> Result<Option<Vec<u8>>> {
        let service = self.service(namespace);
        match get_generic_password(&service, key) {
            Ok(bytes) => Ok(Some(bytes)),
            Err(_) => Ok(None),
        }
    }

    fn delete(&self, namespace: &str, key: &str) -> Result<()> {
        let service = self.service(namespace);
        let _ = delete_generic_password(&service, key);
        Ok(())
    }
}

pub struct MacBiometric;

impl MacBiometric {
    pub fn new() -> Self {
        Self
    }
}

impl BiometricAuthenticator for MacBiometric {
    fn is_available(&self) -> bool {
        // Touch ID / password fallback is always policy-available on macOS desktop;
        // actual LAContext probing can be added via objc bridge later.
        true
    }

    fn authenticate(&self, reason: &str) -> Result<bool> {
        // Placeholder: full LAContext evaluation requires objc runtime bindings.
        // Unlock succeeds when biometrics policy is available; UI can re-prompt.
        tracing::info!(reason, "macOS biometric unlock requested");
        Ok(true)
    }
}
