use std::ffi::{CStr, CString};
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::ptr;
use std::slice;

use crate::world::compile_to_pdf;

thread_local! {
    static LAST_ERROR: std::cell::RefCell<Option<CString>> = const { std::cell::RefCell::new(None) };
}

fn set_last_error(message: impl Into<String>) {
    let cstring = CString::new(message.into()).unwrap_or_else(|_| CString::new("unknown error").unwrap());
    LAST_ERROR.with(|cell| {
        *cell.borrow_mut() = Some(cstring);
    });
}

fn clear_last_error() {
    LAST_ERROR.with(|cell| {
        *cell.borrow_mut() = None;
    });
}

#[no_mangle]
pub extern "C" fn college_typst_compile_pdf(
    source_utf8: *const std::ffi::c_char,
    out_len: *mut usize,
) -> *mut u8 {
    let result = catch_unwind(AssertUnwindSafe(|| compile_pdf_inner(source_utf8, out_len)));
    match result {
        Ok(inner) => inner,
        Err(_) => {
            if !out_len.is_null() {
                unsafe { *out_len = 0 };
            }
            set_last_error("Typst compiler panicked");
            ptr::null_mut()
        }
    }
}

fn compile_pdf_inner(source_utf8: *const std::ffi::c_char, out_len: *mut usize) -> *mut u8 {
    if out_len.is_null() {
        set_last_error("out_len is null");
        return ptr::null_mut();
    }

    unsafe {
        *out_len = 0;
    }

    if source_utf8.is_null() {
        set_last_error("source_utf8 is null");
        return ptr::null_mut();
    }

    let source = unsafe { CStr::from_ptr(source_utf8) };
    let source_str = match source.to_str() {
        Ok(s) => s,
        Err(_) => {
            set_last_error("source_utf8 is not valid UTF-8");
            return ptr::null_mut();
        }
    };

    clear_last_error();

    match compile_to_pdf(source_str) {
        Ok(bytes) => {
            let len = bytes.len();
            let boxed = bytes.into_boxed_slice();
            let ptr = Box::into_raw(boxed);
            unsafe {
                *out_len = len;
            }
            ptr as *mut u8
        }
        Err(message) => {
            set_last_error(message);
            ptr::null_mut()
        }
    }
}

#[no_mangle]
pub extern "C" fn college_typst_free(ptr: *mut u8, len: usize) {
    if ptr.is_null() || len == 0 {
        return;
    }
    let _ = catch_unwind(AssertUnwindSafe(|| {
        unsafe {
            let slice_ptr = slice::from_raw_parts_mut(ptr, len);
            let _ = Box::from_raw(slice_ptr);
        }
    }));
}

#[no_mangle]
pub extern "C" fn college_typst_last_error() -> *const std::ffi::c_char {
    LAST_ERROR.with(|cell| {
        cell.borrow()
            .as_ref()
            .map(|s| s.as_ptr())
            .unwrap_or(ptr::null())
    })
}
