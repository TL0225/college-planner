//! Memory-mapped file I/O for large vault assets and embeddings.

use anyhow::{anyhow, Context, Result};
use std::fs::File;
use std::path::Path;
use windows::Win32::Foundation::HANDLE;
use windows::Win32::Storage::FileSystem::{
    CreateFileW, FILE_ATTRIBUTE_NORMAL, FILE_GENERIC_READ, FILE_SHARE_READ, OPEN_EXISTING,
};
use windows::Win32::System::Memory::{
    CreateFileMappingW, MapViewOfFile, UnmapViewOfFile, FILE_MAP_READ, PAGE_READONLY,
};

fn wide_path(path: &Path) -> Vec<u16> {
    use std::os::windows::prelude::OsStrExt;
    path.as_os_str()
        .encode_wide()
        .chain(std::iter::once(0))
        .collect()
}

/// Memory-map a file read-only and return its byte length.
pub fn mmap_read_only(path: &Path) -> Result<MappedFile> {
    let path_w = wide_path(path);
    unsafe {
        let handle: HANDLE = CreateFileW(
            windows::core::PCWSTR(path_w.as_ptr()),
            FILE_GENERIC_READ.0,
            FILE_SHARE_READ,
            None,
            OPEN_EXISTING,
            FILE_ATTRIBUTE_NORMAL,
            None,
        )?;
        let file = File::open(path).context("open file for metadata")?;
        let len = file.metadata()?.len();
        let mapping = CreateFileMappingW(handle, None, PAGE_READONLY, 0, 0, None)?;
        let view = MapViewOfFile(mapping, FILE_MAP_READ, 0, 0, 0);
        if view.Value.is_null() {
            return Err(anyhow!("MapViewOfFile returned null"));
        }
        Ok(MappedFile {
            _handle: handle,
            _mapping: mapping,
            ptr: view.Value as *const u8,
            len: len as usize,
        })
    }
}

pub struct MappedFile {
    _handle: HANDLE,
    _mapping: windows::Win32::Foundation::HANDLE,
    ptr: *const u8,
    len: usize,
}

impl MappedFile {
    pub fn len(&self) -> usize {
        self.len
    }

    pub fn as_slice(&self) -> &[u8] {
        unsafe { std::slice::from_raw_parts(self.ptr, self.len) }
    }
}

impl Drop for MappedFile {
    fn drop(&mut self) {
        unsafe {
            let _ = UnmapViewOfFile(windows::Win32::System::Memory::MEMORY_MAPPED_VIEW_ADDRESS {
                Value: self.ptr as *mut _,
            });
        }
    }
}
