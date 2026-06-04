// CatalogDegreeTypeFilter.swift
// Feature: Catalog
// Purpose: Catalog module — CatalogDegreeTypeFilter.
// Data: CollegePersistence / repositories when applicable.

import Foundation

/// Strict degree-type matching for catalog program pickers (display suffix + stored tokens).
enum CatalogDegreeTypeFilter {
    /// Normalized tokens used for equality checks (`M.S.` → `MS`, `Ph.D.` → `PHD`).
    static func normalizeToken(_ raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: " ", with: "")
    }

    /// Primary filter token(s) from a picker value — does not expand `MS` into unrelated tokens.
    static func strictFilterTokens(forPickerValue raw: String) -> Set<String> {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var tokens: Set<String> = []

        if let open = trimmed.firstIndex(of: "("),
           let close = trimmed.lastIndex(of: ")"),
           open < close {
            let inner = trimmed[trimmed.index(after: open)..<close]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !inner.isEmpty {
                for part in inner.split(whereSeparator: { "/,+;&".contains($0) }) {
                    let token = normalizeToken(String(part))
                    if !token.isEmpty { tokens.insert(token) }
                }
            }
        }

        let whole = normalizeToken(trimmed)
        if !whole.isEmpty, whole.count <= 8, DegreeTokenRegistry.isKnownToken(whole) {
            tokens.insert(whole)
        }

        if tokens.isEmpty, let lastWord = trimmed.split(separator: " ").last {
            let norm = normalizeToken(String(lastWord))
            if !norm.isEmpty, norm.count <= 8, DegreeTokenRegistry.isLikelyDegreeTypeSuffix(norm) {
                tokens.insert(norm)
            }
        }

        if tokens.isEmpty, let firstWord = trimmed.split(separator: " ").first {
            let norm = normalizeToken(String(firstWord))
            if !norm.isEmpty, norm.count <= 8, DegreeTokenRegistry.isLikelyDegreeTypeSuffix(norm) {
                tokens.insert(norm)
            }
        }

        return tokens
    }

    /// Stable token for local store `DegreeRequirementEntity.degreeType` (e.g. `Master of Science (MS)` → `MS`).
    static func requirementsStorageKey(fromProfileDegreeType raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Unknown" }
        if let canonical = DegreeTypeNormalizer.normalize(trimmed) {
            return canonical.storageToken
        }
        let tokens = strictFilterTokens(forPickerValue: trimmed).sorted { $0.count < $1.count }
        if let short = tokens.first, !short.isEmpty { return short }
        return trimmed
    }

    /// Suffix token parsed from a catalog display name (text after the last comma).
    static func suffixToken(fromDisplayName displayName: String) -> String? {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains(",") else { return nil }
        let suffix = trimmed.split(separator: ",").last.map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !suffix.isEmpty else { return nil }
        return normalizeToken(suffix)
    }

    static func displayName(_ displayName: String, matchesPicker pickerValue: String) -> Bool {
        let allowed = strictFilterTokens(forPickerValue: pickerValue)
        guard !allowed.isEmpty else { return true }

        if let suffix = suffixToken(fromDisplayName: displayName), !suffix.isEmpty {
            return allowed.contains(suffix)
        }

        let normalizedDisplay = normalizeToken(displayName)
        return allowed.contains(normalizedDisplay)
    }

    /// Tab / header label: prefer configured full title; otherwise expand common catalog tokens.
    static func tabDisplayLabel(forDegreeType raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        for level in DegreeConfiguration.degreeLevels {
            if let exact = level.types.first(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
                return labelWithoutParentheticalAcronym(exact)
            }
        }

        let pickerToken = strictFilterTokens(forPickerValue: trimmed).sorted { $0.count > $1.count }.first
        if let pickerToken {
            for level in DegreeConfiguration.degreeLevels {
                for type in level.types {
                    let short = DegreeConfiguration.shortForm(from: type)
                    if normalizeToken(short) == pickerToken {
                        return labelWithoutParentheticalAcronym(type)
                    }
                }
            }
            if let expanded = DegreeTokenRegistry.displayLabel(forNormalizedToken: pickerToken) {
                return expanded
            }
        }

        if let canonical = DegreeTypeNormalizer.normalize(trimmed) {
            return canonical.displayLabel.isEmpty ? trimmed : canonical.displayLabel
        }

        if trimmed.contains("(") {
            return labelWithoutParentheticalAcronym(trimmed)
        }
        return trimmed
    }

    private static func labelWithoutParentheticalAcronym(_ full: String) -> String {
        let trimmed = full.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let open = trimmed.firstIndex(of: "(") else { return trimmed }
        return trimmed[..<open].trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
