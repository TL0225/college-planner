// CatalogCourseCodeHelpers.swift
// Feature: Catalog
// Purpose: Catalog module — CatalogCourseCodeHelpers.
// Data: CollegePersistence / repositories when applicable.

import Foundation

/// Catalog course-code heuristics (Phase 7f — moved off local store).
enum CatalogCourseCodeHelpers {
    /// True when the user is typing a course code / subject prefix (not a title keyword).
    static func queryLooksLikeCourseCode(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return false }
        let letters = trimmed.filter(\.isLetter).count
        guard letters >= 2 else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-– "))
        guard trimmed.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return false }

        if trimmed.contains(where: \.isNumber) { return true }
        if trimmed.range(
            of: #"[A-Za-z]{2,}[-–][A-Za-z]{1,}"#,
            options: .regularExpression
        ) != nil {
            return true
        }
        return false
    }

    /// Uppercase alphanumeric key for catalog code matching (strips spaces and punctuation).
    static func compactCatalogCourseCode(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map { String($0) }
            .joined()
    }
}
