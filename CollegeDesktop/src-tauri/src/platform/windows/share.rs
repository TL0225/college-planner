//! Windows Share contract (shell invoke) and multi-format clipboard.

use anyhow::{anyhow, Context, Result};
use std::ffi::OsStr;
use std::os::windows::ffi::OsStrExt;
use std::path::Path;
use windows::core::PCWSTR;
use windows::Win32::Foundation::{HANDLE, HWND};
use windows::Win32::System::DataExchange::{
    CloseClipboard, EmptyClipboard, OpenClipboard, SetClipboardData,
};
use windows::Win32::System::Memory::{GlobalAlloc, GlobalLock, GlobalUnlock, GMEM_MOVEABLE};
use windows::Win32::System::Ole::CF_UNICODETEXT;
use windows::Win32::UI::Shell::ShellExecuteW;
use windows::Win32::UI::WindowsAndMessaging::SW_SHOWNORMAL;

fn wide(s: &str) -> Vec<u16> {
    OsStr::new(s)
        .encode_wide()
        .chain(std::iter::once(0))
        .collect()
}

/// Open the native Windows share UI for a file via shell "share" verb.
pub fn share_file(path: &Path) -> Result<()> {
    if !path.exists() {
        return Err(anyhow!("file not found: {}", path.display()));
    }
    let path_w = wide(&path.to_string_lossy());
    unsafe {
        let result = ShellExecuteW(
            None,
            PCWSTR(wide("share").as_ptr()),
            PCWSTR(path_w.as_ptr()),
            PCWSTR::null(),
            PCWSTR::null(),
            SW_SHOWNORMAL,
        );
        if (result.0 as isize) <= 32 {
            return Err(anyhow!("ShellExecuteW share failed"));
        }
    }
    Ok(())
}

/// Copy multi-format text to the Windows clipboard (Unicode plain text).
pub fn copy_rich_text(plain: &str, html: Option<&str>) -> Result<()> {
    let plain_w: Vec<u16> = OsStr::new(plain)
        .encode_wide()
        .chain(std::iter::once(0))
        .collect();

    unsafe {
        OpenClipboard(HWND::default()).context("OpenClipboard")?;
        EmptyClipboard().context("EmptyClipboard")?;

        let byte_len = plain_w.len() * 2;
        let hglobal = GlobalAlloc(GMEM_MOVEABLE, byte_len)?;
        let ptr = GlobalLock(hglobal) as *mut u16;
        std::ptr::copy_nonoverlapping(plain_w.as_ptr(), ptr, plain_w.len());
        let _ = GlobalUnlock(hglobal);
        SetClipboardData(CF_UNICODETEXT.0 as u32, HANDLE(hglobal.0))?;
        CloseClipboard()?;
    }

    if let Some(html_body) = html {
        tracing::debug!(len = html_body.len(), "HTML clipboard format deferred (CF_HTML)");
    }
    Ok(())
}
