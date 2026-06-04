// CollegeCoreSwift.swift
// Feature: Rust
// Purpose: Rust module — CollegeCore.
// Data: CollegePersistence / repositories when applicable.

// CollegeCoreSwift.swift
//
// Swift-friendly wrappers around the Rust `college-core` C API.
//
// IMPORTANT: This file requires libcollege_core.a to be linked.
// Run `./rust-core/build_macos.sh` once and follow the Xcode setup
// instructions printed at the end of that script.
//
// Until the library is linked, the fallback implementations below will be
// used so the Swift target continues to compile and run without Rust.

import Foundation
import os

/// Namespace for high-performance Rust-backed string and HTML utilities.
///
/// Each method automatically falls back to a pure-Swift implementation when
/// `libcollege_core.a` has not been linked yet, so you can integrate
/// incrementally without breaking the build.
enum CollegeCore {
    private static let performanceLog = OSLog(subsystem: "Timothy.College", category: .pointsOfInterest)

    // MARK: - Prerequisite parsing

    /// Parses a prerequisite string and returns a JSON-encoded AST, or `nil`.
    ///
    /// Example:
    /// ```swift
    /// let json = CollegeCore.parsePrereq("CSE 116 or (CSE 113 and MTH 142)")
    /// // → {"type":"or","children":[{"type":"course","code":"CSE 116"}, ...]}
    /// ```
    static func parsePrereq(_ input: String) -> String? {
        #if COLLEGE_CORE_RUST_LINKED
        return input.withCString { ptr in
            guard let result = college_core_parse_prereq(ptr) else { return nil }
            defer { college_core_free_string(result) }
            return String(cString: result)
        }
        #else
        // Swift fallback: returns nil (handled by caller falling back to LLM)
        return nil
        #endif
    }

    /// Extracts all course codes from a prerequisite string.
    ///
    /// Returns an array of normalized codes, e.g. `["CSE 116", "MTH 142"]`.
    static func extractCourseCodes(from text: String) -> [String] {
        let signpostID = OSSignpostID(log: performanceLog)
        os_signpost(.begin, log: performanceLog, name: "CollegeCore.ExtractCourseCodes", signpostID: signpostID)
        defer { os_signpost(.end, log: performanceLog, name: "CollegeCore.ExtractCourseCodes", signpostID: signpostID) }
        #if COLLEGE_CORE_RUST_LINKED
        return text.withCString { ptr in
            let result = college_core_extract_course_codes(ptr)!
            defer { college_core_free_string(result) }
            let json = String(cString: result)
            return parseJSONStringArray(json) ?? []
        }
        #else
        // Swift fallback: simple regex-based extraction
        return swiftExtractCourseCodes(from: text)
        #endif
    }

    /// Normalizes a course code string (upper-case, collapse whitespace).
    static func normalizeCourseCode(_ raw: String) -> String {
        let signpostID = OSSignpostID(log: performanceLog)
        os_signpost(.begin, log: performanceLog, name: "CollegeCore.NormalizeCourseCode", signpostID: signpostID)
        defer { os_signpost(.end, log: performanceLog, name: "CollegeCore.NormalizeCourseCode", signpostID: signpostID) }
        #if COLLEGE_CORE_RUST_LINKED
        return raw.withCString { ptr in
            let result = college_core_normalize_course_code(ptr)!
            defer { college_core_free_string(result) }
            return String(cString: result)
        }
        #else
        return swiftNormalizeCourseCode(raw)
        #endif
    }

    // MARK: - HTML utilities

    /// Extracts hrefs from `<a>` tags whose href contains `needle`.
    ///
    /// Equivalent to SwiftSoup's `doc.select("a[href*=\(needle)]").map { $0.attr("href") }`
    /// but 5–10× faster for large HTML documents.
    static func extractLinks(from html: String, containing needle: String) -> [String] {
        #if COLLEGE_CORE_RUST_LINKED
        return html.withCString { htmlPtr in
            needle.withCString { needlePtr in
                let result = college_core_extract_links_containing(htmlPtr, needlePtr)!
                defer { college_core_free_string(result) }
                return parseJSONStringArray(String(cString: result)) ?? []
            }
        }
        #else
        // Swift fallback: use regex
        return swiftExtractLinks(from: html, containing: needle)
        #endif
    }

    /// Returns the text content of all elements matching a simple CSS selector.
    ///
    /// Supported: tag names, `.class`, `#id`, `[attr]`.
    static func selectText(in html: String, selector: String) -> [String] {
        #if COLLEGE_CORE_RUST_LINKED
        return html.withCString { htmlPtr in
            selector.withCString { selPtr in
                let result = college_core_select_text(htmlPtr, selPtr)!
                defer { college_core_free_string(result) }
                return parseJSONStringArray(String(cString: result)) ?? []
            }
        }
        #else
        return []  // fallback handled by calling site (SwiftSoup)
        #endif
    }

    // MARK: - Helpers

    private static func parseJSONStringArray(_ json: String) -> [String]? {
        guard let data = json.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [String]
        else { return nil }
        return array
    }

    // MARK: - Swift fallbacks (used when Rust library is not linked)

    private static func swiftNormalizeCourseCode(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
    }

    private static func swiftExtractCourseCodes(from text: String) -> [String] {
        guard let regex = try? NSRegularExpression(
            pattern: "\\b([A-Z]{2,4})[\\s\u{00A0}]?([0-9]{3,4})\\b",
            options: []
        ) else { return [] }
        let nsText = text.uppercased() as NSString
        let matches = regex.matches(in: text.uppercased(), range: NSRange(location: 0, length: nsText.length))
        var seen = Set<String>()
        var result: [String] = []
        for match in matches {
            let letters = nsText.substring(with: match.range(at: 1))
            let digits  = nsText.substring(with: match.range(at: 2))
            let code = "\(letters) \(digits)"
            if seen.insert(code).inserted {
                result.append(code)
            }
        }
        return result
    }

    private static func swiftExtractLinks(from html: String, containing needle: String) -> [String] {
        // Minimal fallback — actual callers should use SwiftSoup when Rust is not available
        var links: [String] = []
        let pattern = #"href="([^"]*)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsHtml = html as NSString
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: nsHtml.length))
        for match in matches {
            let href = nsHtml.substring(with: match.range(at: 1))
            if href.contains(needle) {
                links.append(href)
            }
        }
        return links
    }
}
