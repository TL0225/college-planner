use anyhow::Result;

pub trait CredentialStore: Send + Sync {
    fn set(&self, namespace: &str, key: &str, value: &[u8]) -> Result<()>;
    fn get(&self, namespace: &str, key: &str) -> Result<Option<Vec<u8>>>;
    fn delete(&self, namespace: &str, key: &str) -> Result<()>;
}

pub trait BiometricAuthenticator: Send + Sync {
    fn is_available(&self) -> bool;
    fn authenticate(&self, reason: &str) -> Result<bool>;
}
