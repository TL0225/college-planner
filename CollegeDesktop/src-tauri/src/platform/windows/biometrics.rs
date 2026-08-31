//! Windows Hello via UserConsentVerifier (WinRT) with HWND interop for Win32.

use crate::security::traits::BiometricAuthenticator;
use anyhow::{anyhow, Result};
use std::sync::OnceLock;
use windows::core::{factory, HSTRING};
use windows::Foundation::IAsyncOperation;
use windows::Security::Credentials::UI::{
    UserConsentVerifier, UserConsentVerificationResult, UserConsentVerifierAvailability,
};
use windows::Win32::Foundation::HWND;
use windows::Win32::System::WinRT::IUserConsentVerifierInterop;
use windows::Win32::UI::WindowsAndMessaging::GetForegroundWindow;

static MAIN_HWND: OnceLock<isize> = OnceLock::new();

/// Store the main window handle so Hello prompts parent correctly.
pub fn set_main_hwnd(hwnd: HWND) {
    let _ = MAIN_HWND.set(hwnd.0 as isize);
}

fn parent_hwnd() -> HWND {
    let raw = MAIN_HWND
        .get()
        .copied()
        .unwrap_or_else(|| unsafe { GetForegroundWindow().0 as isize });
    HWND(raw as *mut _)
}

pub struct WindowsHelloBiometric;

impl WindowsHelloBiometric {
    pub fn new() -> Self {
        Self
    }
}

impl BiometricAuthenticator for WindowsHelloBiometric {
    fn is_available(&self) -> bool {
        match UserConsentVerifier::CheckAvailabilityAsync()
            .and_then(|op| op.get())
        {
            Ok(UserConsentVerifierAvailability::Available) => true,
            Ok(_) => false,
            Err(e) => {
                tracing::warn!(error = %e, "UserConsentVerifier::CheckAvailability failed");
                false
            }
        }
    }

    fn authenticate(&self, reason: &str) -> Result<bool> {
        tracing::info!(reason, "Windows Hello unlock requested");

        let result = request_verification(reason)?;
        Ok(result == UserConsentVerificationResult::Verified)
    }
}

/// Win32 desktop apps must use IUserConsentVerifierInterop (HWND-parented async op).
fn request_verification(message: &str) -> Result<UserConsentVerificationResult> {
    let hwnd = parent_hwnd();
    let interop = factory::<UserConsentVerifier, IUserConsentVerifierInterop>()
        .map_err(|e| anyhow!("UserConsentVerifier factory: {e}"))?;

    let operation: IAsyncOperation<UserConsentVerificationResult> = unsafe {
        interop
            .RequestVerificationForWindowAsync(hwnd, &HSTRING::from(message))
            .map_err(|e| anyhow!("RequestVerificationForWindowAsync: {e}"))?
    };

    operation
        .get()
        .map_err(|e| anyhow!("Windows Hello verification: {e}"))
}
