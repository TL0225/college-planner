/**
 * college_core.h
 *
 * C API for the Rust `college-core` static library.
 *
 * Swift integration
 * -----------------
 * 1. Build the library:  `./rust-core/build_macos.sh`
 * 2. In Xcode, add `libcollege_core.a` (from `rust-core/build/`) to
 *    "Link Binary with Libraries" in the College target's Build Phases.
 * 3. Add `rust-core/include/` to the target's Header Search Paths.
 * 4. Create (or update) `College/Rust/CollegeCore-Bridging-Header.h` and
 *    `#include "college_core.h"`.
 *
 * Memory contract
 * ---------------
 * Every non-NULL `char *` **returned** by these functions is heap-allocated
 * by Rust and MUST be freed by the caller via `college_core_free_string()`.
 * Never pass Rust-owned strings to `free()` or Swift's `String(cString:)` will
 * double-free.
 *
 * Null safety
 * -----------
 * Input pointers that are documented as non-null will cause a crash (abort)
 * if NULL is passed; the Swift wrapper in CollegeCoreSwift.swift checks
 * for nil before forwarding to these functions.
 */

#pragma once
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Frees a string previously returned by any `college_core_*` function.
 * Passing a NULL pointer is a no-op. Passing any other pointer is UB.
 */
void college_core_free_string(char *ptr);

/**
 * Parses a prerequisite string and returns a JSON-encoded prerequisite tree,
 * or NULL if the input is empty / unparseable.
 *
 * JSON schema:
 *   {"type":"course","code":"CSE 116"}
 *   {"type":"and","children":[...]}
 *   {"type":"or","children":[...]}
 *   {"type":"text","value":"..."}
 *
 * @param input  Null-terminated UTF-8 prerequisite string.
 * @return       Heap-allocated JSON string (caller must free) or NULL.
 */
char *college_core_parse_prereq(const char *input);

/**
 * Extracts all course codes (e.g. "CSE 116") from `input` and returns them
 * as a JSON array of strings (e.g. `["CSE 116","MTH 142"]`).
 *
 * Never returns NULL — returns `"[]"` for empty/error inputs.
 *
 * @param input  Null-terminated UTF-8 string.
 * @return       Heap-allocated JSON array string (caller must free).
 */
char *college_core_extract_course_codes(const char *input);

/**
 * Normalizes a course-code string: upper-case, collapse whitespace, strip
 * non-breaking spaces (U+00A0).
 *
 * Never returns NULL — returns an empty string on error.
 *
 * @param input  Null-terminated UTF-8 string.
 * @return       Heap-allocated normalized string (caller must free).
 */
char *college_core_normalize_course_code(const char *input);

/**
 * Extracts all href attributes from `<a>` tags in `html` whose href contains
 * `needle`, returning them as a JSON array of strings.
 *
 * Never returns NULL — returns `"[]"` for empty/error inputs.
 *
 * @param html    Null-terminated UTF-8 HTML string.
 * @param needle  Null-terminated UTF-8 substring to filter on.
 * @return        Heap-allocated JSON array string (caller must free).
 */
char *college_core_extract_links_containing(const char *html, const char *needle);

/**
 * Extracts the text content of all elements matching `css_selector` in `html`.
 *
 * Supported selectors: tag names, `.class`, `#id`, `[attr]`.
 * Returns a JSON array of strings. Never returns NULL.
 *
 * @param html          Null-terminated UTF-8 HTML string.
 * @param css_selector  Null-terminated CSS selector string.
 * @return              Heap-allocated JSON array string (caller must free).
 */
char *college_core_select_text(const char *html, const char *css_selector);

#ifdef __cplusplus
}
#endif
