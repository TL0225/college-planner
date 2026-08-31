//! Windows 11 EcoQoS efficiency mode and power status.

use anyhow::{anyhow, Result};
use windows::Win32::System::Threading::{
    GetCurrentProcess, SetProcessInformation, PROCESS_POWER_THROTTLING_CURRENT_VERSION,
    PROCESS_POWER_THROTTLING_EXECUTION_SPEED, PROCESS_POWER_THROTTLING_STATE,
    ProcessPowerThrottling,
};

/// Enable Windows 11 Efficiency Mode (EcoQoS) for background work.
pub fn enable_efficiency_mode(on: bool) -> Result<()> {
    let mut state = PROCESS_POWER_THROTTLING_STATE {
        Version: PROCESS_POWER_THROTTLING_CURRENT_VERSION,
        ControlMask: PROCESS_POWER_THROTTLING_EXECUTION_SPEED,
        StateMask: if on {
            PROCESS_POWER_THROTTLING_EXECUTION_SPEED
        } else {
            0
        },
    };
    unsafe {
        SetProcessInformation(
            GetCurrentProcess(),
            ProcessPowerThrottling,
            &mut state as *mut _ as *mut _,
            std::mem::size_of::<PROCESS_POWER_THROTTLING_STATE>() as u32,
        )
        .map_err(|e| anyhow!("SetProcessInformation(ProcessPowerThrottling): {e}"))?;
    }
    tracing::info!(on, "Windows EcoQoS efficiency mode updated");
    Ok(())
}

/// Query battery saver via SYSTEM_POWER_STATUS (simplified).
pub fn battery_saver_active() -> bool {
  use windows::Win32::System::Power::{GetSystemPowerStatus, SYSTEM_POWER_STATUS};
  unsafe {
    let mut status = SYSTEM_POWER_STATUS::default();
    if GetSystemPowerStatus(&mut status).is_ok() {
      return status.SystemStatusFlag & 1 != 0;
    }
  }
  false
}
