//! LocalAuthentication (LAContext) — Touch ID / password policy.

use crate::security::traits::BiometricAuthenticator;
use anyhow::{anyhow, Result};
use block2::RcBlock;
use objc2::rc::Retained;
use objc2::runtime::Bool;
use objc2_foundation::NSString;
use objc2_local_authentication::{LAContext, LAPolicy};
use std::sync::mpsc;
use std::time::Duration;

pub struct MacLocalAuthBiometric;

impl MacLocalAuthBiometric {
    pub fn new() -> Self {
        Self
    }

    fn fresh_context() -> Retained<LAContext> {
        // Fresh context per evaluation so a prior failure never satisfies a later prompt.
        unsafe { LAContext::new() }
    }
}

impl BiometricAuthenticator for MacLocalAuthBiometric {
    fn is_available(&self) -> bool {
        let ctx = Self::fresh_context();
        let policy = LAPolicy::DeviceOwnerAuthentication;
        unsafe { ctx.canEvaluatePolicy_error(policy).is_ok() }
    }

    fn authenticate(&self, reason: &str) -> Result<bool> {
        tracing::info!(reason, "macOS LocalAuthentication unlock requested");

        let ctx = Self::fresh_context();
        let policy = LAPolicy::DeviceOwnerAuthentication;
        if unsafe { ctx.canEvaluatePolicy_error(policy) }.is_err() {
            return Ok(false);
        }

        let reason_ns = NSString::from_str(reason);
        let (tx, rx) = mpsc::channel::<(bool, Option<i32>)>();
        let tx = std::sync::Arc::new(std::sync::Mutex::new(Some(tx)));

        let tx_cb = tx.clone();
        let block = RcBlock::new(move |success: Bool, error: *mut objc2_foundation::NSError| {
            let code = if error.is_null() {
                None
            } else {
                Some(unsafe { (*error).code() })
            };
            if let Ok(mut guard) = tx_cb.lock() {
                if let Some(sender) = guard.take() {
                    let _ = sender.send((success.as_bool(), code));
                }
            }
        });

        let dyn_block: &block2::DynBlock<dyn Fn(Bool, *mut objc2_foundation::NSError)> = &block;
        unsafe {
            ctx.evaluatePolicy_localizedReason_reply(policy, &reason_ns, dyn_block);
        }

        match rx.recv_timeout(Duration::from_secs(120)) {
            Ok((true, _)) => Ok(true),
            Ok((false, Some(code))) => {
                tracing::info!(code, "LocalAuthentication denied or cancelled");
                Ok(false)
            }
            Ok((false, None)) => Ok(false),
            Err(_) => Err(anyhow!("LocalAuthentication timed out")),
        }
    }
}
