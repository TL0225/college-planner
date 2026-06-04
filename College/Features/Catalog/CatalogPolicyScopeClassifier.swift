// CatalogPolicyScopeClassifier.swift
// Feature: Catalog
// Purpose: Catalog module — CatalogPolicyScope.
// Data: CollegePersistence / repositories when applicable.

import Foundation

/// Normalized policy scope stored on ``CatalogPolicyDocumentEntity`` / chunk metadata (`undergraduate`, `graduate`, `shared`).
enum CatalogPolicyScope: String, Sendable, CaseIterable {
    case undergraduate
    case graduate
    case shared
}

enum CatalogPolicyScopeClassifier {
    /// Derives scope from the catalog’s normalized label (see ``ModernCampusCatalogLabels``) plus optional nav link text.
    static func scope(catalogTypeLabel: String, navLinkText: String? = nil) -> CatalogPolicyScope {
        let label = catalogTypeLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = label.lowercased()

        // "undergraduate" contains the substring "graduate" — classify undergraduate first.
        if lower.contains("undergraduate") {
            return .undergraduate
        }
        if lower.contains("graduate") || lower.contains("phd") || lower.contains("doctoral") {
            return .graduate
        }
        if lower.contains("law") || lower.contains("dental") || lower.contains("medical") || lower.contains("jsmbs") {
            return .graduate
        }

        if let nav = navLinkText?.trimmingCharacters(in: .whitespacesAndNewlines), !nav.isEmpty {
            let n = nav.lowercased()
            if n.contains("undergraduate") || n.contains(" undergrad") { return .undergraduate }
            if n.contains("doctoral") { return .graduate }
            if n.contains("graduate") { return .graduate }
        }

        return .shared
    }

    /// Maps a student profile / catalog tier string to the filter token used in `CatalogVectorStore.searchHybrid`.
    static func retrievalFilterToken(degreeLevel: String?, degreeType: String?) -> String? {
        let level = (degreeLevel ?? "").lowercased()
        let dtype = (degreeType ?? "").lowercased()

        if level.contains("undergraduate") {
            return CatalogPolicyScope.undergraduate.rawValue
        }
        if level.contains("graduate") || level.contains("master") || level.contains("phd") || level.contains("doctoral")
            || level.contains("law") || level.contains("medic") || level.contains("dental") {
            return CatalogPolicyScope.graduate.rawValue
        }
        if dtype.contains("phd") || dtype.contains("jd") || dtype.contains("md ") || dtype.contains("dds")
            || dtype.contains("dmd") {
            return CatalogPolicyScope.graduate.rawValue
        }
        if level.isEmpty {
            return CatalogPolicyScope.undergraduate.rawValue
        }
        return nil
    }

    /// Whether a chunk with `chunkScope` should appear when the student filter is `filter` (nil = no filter).
    static func chunkMatchesCatalogScopeFilter(chunkScope: String?, filter: String?) -> Bool {
        guard let filter, !filter.isEmpty else { return true }
        guard let raw = chunkScope?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !raw.isEmpty else {
            return true
        }
        if raw == CatalogPolicyScope.shared.rawValue { return true }
        return raw == filter
    }
}
