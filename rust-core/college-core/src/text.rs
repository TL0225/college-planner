// college-core/src/text.rs
//
// String utilities: course-code normalization and extraction.

/// Normalizes a course code string:
/// - Replaces non-breaking spaces (U+00A0) with regular spaces
/// - Collapses consecutive whitespace into a single space
/// - Trims leading/trailing whitespace
/// - Converts to uppercase
pub fn normalize_course_code(raw: &str) -> String {
    // Replace NBSP and other exotic spaces
    let replaced: String = raw
        .chars()
        .map(|c| if c == '\u{00A0}' || c.is_whitespace() { ' ' } else { c })
        .collect();

    // Collapse runs of spaces
    let mut result = String::with_capacity(replaced.len());
    let mut prev_space = true; // treat leading chars as "just saw a space"
    for c in replaced.chars() {
        if c == ' ' {
            if !prev_space {
                result.push(' ');
            }
            prev_space = true;
        } else {
            result.push(c.to_uppercase().next().unwrap_or(c));
            prev_space = false;
        }
    }

    // Trim trailing space added by the loop
    if result.ends_with(' ') {
        result.pop();
    }
    result
}

/// Extracts all course codes from a prerequisite string.
///
/// A course code is defined as:
///   2–4 uppercase ASCII letters, optional space, 3–4 ASCII digits
///
/// Examples: "CSE 116", "MTH142", "BISC 241"
pub fn extract_course_codes(text: &str) -> Vec<String> {
    let mut codes = Vec::new();
    let bytes = text.as_bytes();
    let len = bytes.len();
    let mut i = 0;

    while i < len {
        // Look for a run of 2–4 ASCII alpha characters
        if bytes[i].is_ascii_alphabetic() {
            let alpha_start = i;
            while i < len && bytes[i].is_ascii_alphabetic() {
                i += 1;
            }
            let alpha_len = i - alpha_start;

            if alpha_len >= 2 && alpha_len <= 4 {
                // Optional single space
                let had_space = if i < len && bytes[i] == b' ' {
                    i += 1;
                    true
                } else {
                    false
                };

                // Must be followed by 3–4 digits
                if i < len && bytes[i].is_ascii_digit() {
                    let digit_start = i;
                    while i < len && bytes[i].is_ascii_digit() {
                        i += 1;
                    }
                    let digit_len = i - digit_start;

                    if digit_len >= 3 && digit_len <= 4 {
                        // Check that the character before alpha_start is a word boundary
                        let before_ok = alpha_start == 0
                            || !bytes[alpha_start - 1].is_ascii_alphanumeric();
                        // Check that the character after digits is a word boundary
                        let after_ok = i >= len || !bytes[i].is_ascii_alphanumeric();

                        if before_ok && after_ok {
                            let alpha: &str = &text[alpha_start..alpha_start + alpha_len];
                            let digits: &str = &text[digit_start..digit_start + digit_len];
                            let code = if had_space {
                                format!("{} {}", alpha.to_uppercase(), digits)
                            } else {
                                format!("{}{}", alpha.to_uppercase(), digits)
                            };
                            codes.push(code);
                            continue;
                        }
                    }
                }
                // Not a valid course — backtrack the space if we consumed it
                if had_space {
                    i -= 1;
                }
            }
        } else {
            i += 1;
        }
    }

    // Deduplicate while preserving order
    let mut seen = std::collections::HashSet::new();
    codes.retain(|c| seen.insert(c.clone()));
    codes
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_normalize_basic() {
        assert_eq!(normalize_course_code("cse  116"), "CSE 116");
    }

    #[test]
    fn test_normalize_nbsp() {
        // Non-breaking space between letters and digits
        assert_eq!(normalize_course_code("CSE\u{00A0}116"), "CSE 116");
    }

    #[test]
    fn test_normalize_trim() {
        assert_eq!(normalize_course_code("  mth 142  "), "MTH 142");
    }

    #[test]
    fn test_extract_simple() {
        let codes = extract_course_codes("Prereq: CSE 116 or CSE 113 and MTH 142");
        assert!(codes.contains(&"CSE 116".to_string()));
        assert!(codes.contains(&"CSE 113".to_string()));
        assert!(codes.contains(&"MTH 142".to_string()));
    }

    #[test]
    fn test_extract_no_space() {
        let codes = extract_course_codes("MTH142");
        assert_eq!(codes, vec!["MTH142".to_string()]);
    }

    #[test]
    fn test_extract_dedup() {
        let codes = extract_course_codes("CSE 116 or CSE 116");
        assert_eq!(codes.len(), 1);
    }

    #[test]
    fn test_extract_ignores_non_course() {
        // "GPA" has 3 letters but no digits
        let codes = extract_course_codes("Requires GPA of 2.0");
        assert!(codes.is_empty());
    }
}
