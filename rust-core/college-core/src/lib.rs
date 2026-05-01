// college-core/src/lib.rs
//
// C-ABI surface exposed to Swift via a bridging header.
// Each function uses raw C strings (null-terminated *const c_char) and
// returns heap-allocated strings that the Swift caller must free with
// college_core_free_string().
//
// Thread-safety: all public functions are stateless and therefore safe
// to call from any thread (including Swift async contexts).

#![allow(clippy::missing_safety_doc)]

mod prereq;
mod text;
mod html_parser;

use std::ffi::{CStr, CString};
use std::os::raw::c_char;

/// Frees a string previously returned by any college_core_* function.
///
/// # Safety
/// `ptr` MUST have been returned by a college_core_* function.
/// Passing any other pointer is undefined behaviour.
#[no_mangle]
pub unsafe extern "C" fn college_core_free_string(ptr: *mut c_char) {
    if ptr.is_null() {
        return;
    }
    drop(CString::from_raw(ptr));
}

/// Parses a prerequisite string (e.g. "CSE 116 or (CSE 113 and MTH 142)")
/// and returns a JSON-encoded `PrereqRule` AST, or NULL on parse failure.
///
/// The caller owns the returned string and must call `college_core_free_string`.
///
/// # Safety
/// `input` must be a valid, null-terminated UTF-8 C string.
#[no_mangle]
pub unsafe extern "C" fn college_core_parse_prereq(input: *const c_char) -> *mut c_char {
    if input.is_null() {
        return std::ptr::null_mut();
    }
    let s = match CStr::from_ptr(input).to_str() {
        Ok(v) => v,
        Err(_) => return std::ptr::null_mut(),
    };
    match prereq::parse_to_json(s) {
        Some(json) => match CString::new(json) {
            Ok(c) => c.into_raw(),
            Err(_) => std::ptr::null_mut(),
        },
        None => std::ptr::null_mut(),
    }
}

/// Extracts all course codes (e.g. "CSE 116", "MTH 142") from a
/// prerequisites string and returns them as a JSON array of strings.
///
/// Returns `"[]"` (never NULL) so callers don't need null checks.
///
/// # Safety
/// `input` must be a valid, null-terminated UTF-8 C string.
#[no_mangle]
pub unsafe extern "C" fn college_core_extract_course_codes(input: *const c_char) -> *mut c_char {
    if input.is_null() {
        let empty = CString::new("[]").unwrap();
        return empty.into_raw();
    }
    let s = match CStr::from_ptr(input).to_str() {
        Ok(v) => v,
        Err(_) => {
            return CString::new("[]").unwrap().into_raw();
        }
    };
    let codes = text::extract_course_codes(s);
    let json = serde_json_encode_string_array(&codes);
    CString::new(json).unwrap_or_else(|_| CString::new("[]").unwrap()).into_raw()
}

/// Normalizes a course-code string (upper-case, collapse whitespace, strip
/// non-breaking spaces) and returns the result.
///
/// Returns an empty string ("") rather than NULL on error.
///
/// # Safety
/// `input` must be a valid, null-terminated UTF-8 C string.
#[no_mangle]
pub unsafe extern "C" fn college_core_normalize_course_code(input: *const c_char) -> *mut c_char {
    if input.is_null() {
        return CString::new("").unwrap().into_raw();
    }
    let s = match CStr::from_ptr(input).to_str() {
        Ok(v) => v,
        Err(_) => return CString::new("").unwrap().into_raw(),
    };
    let normalized = text::normalize_course_code(s);
    CString::new(normalized).unwrap_or_else(|_| CString::new("").unwrap()).into_raw()
}

/// Extracts all href attributes from `<a>` tags in an HTML string whose
/// href contains `needle`, returning them as a JSON array of strings.
///
/// Intended for catalog-sidebar link extraction — much faster than SwiftSoup
/// because html5ever's tokenizer never builds a full DOM.
///
/// # Safety
/// Both `html` and `needle` must be valid null-terminated UTF-8 C strings.
#[no_mangle]
pub unsafe extern "C" fn college_core_extract_links_containing(
    html: *const c_char,
    needle: *const c_char,
) -> *mut c_char {
    let empty = || CString::new("[]").unwrap().into_raw();
    if html.is_null() || needle.is_null() {
        return empty();
    }
    let html_str = match CStr::from_ptr(html).to_str() {
        Ok(v) => v,
        Err(_) => return empty(),
    };
    let needle_str = match CStr::from_ptr(needle).to_str() {
        Ok(v) => v,
        Err(_) => return empty(),
    };
    let links = html_parser::extract_links_containing(html_str, needle_str);
    let json = serde_json_encode_string_array(&links);
    CString::new(json).unwrap_or_else(|_| CString::new("[]").unwrap()).into_raw()
}

/// Extracts the text content of every element matching `css_selector` in `html`.
/// Returns a JSON array of strings.
///
/// Supported selectors: tag names, `.class`, `#id`, and simple attribute
/// presence (`[attr]`). For complex selectors, fall back to SwiftSoup.
///
/// # Safety
/// Both `html` and `css_selector` must be valid null-terminated UTF-8 C strings.
#[no_mangle]
pub unsafe extern "C" fn college_core_select_text(
    html: *const c_char,
    css_selector: *const c_char,
) -> *mut c_char {
    let empty = || CString::new("[]").unwrap().into_raw();
    if html.is_null() || css_selector.is_null() {
        return empty();
    }
    let html_str = match CStr::from_ptr(html).to_str() {
        Ok(v) => v,
        Err(_) => return empty(),
    };
    let sel_str = match CStr::from_ptr(css_selector).to_str() {
        Ok(v) => v,
        Err(_) => return empty(),
    };
    let texts = html_parser::select_text(html_str, sel_str);
    let json = serde_json_encode_string_array(&texts);
    CString::new(json).unwrap_or_else(|_| CString::new("[]").unwrap()).into_raw()
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

/// Manual JSON array encoder — avoids pulling in `serde_json` into this crate.
fn serde_json_encode_string_array(arr: &[String]) -> String {
    let mut out = String::with_capacity(arr.iter().map(|s| s.len() + 4).sum::<usize>() + 2);
    out.push('[');
    for (i, s) in arr.iter().enumerate() {
        if i > 0 {
            out.push(',');
        }
        out.push('"');
        for c in s.chars() {
            match c {
                '"' => out.push_str("\\\""),
                '\\' => out.push_str("\\\\"),
                '\n' => out.push_str("\\n"),
                '\r' => out.push_str("\\r"),
                '\t' => out.push_str("\\t"),
                c => out.push(c),
            }
        }
        out.push('"');
    }
    out.push(']');
    out
}
