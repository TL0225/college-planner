// DegreeTypeNormalizer.swift
// Feature: Catalog
// Purpose: Catalog module — CanonicalDegreeType.
// Data: CollegePersistence / repositories when applicable.

import Foundation

/// Canonical degree metadata after normalization from any input format.
struct CanonicalDegreeType: Equatable {
    let token: String?
    let fullLabel: String?
    let displayLabel: String
    let degreeLevel: String
    let isConfirmed: Bool

    var storageToken: String {
        if let token, !token.isEmpty { return token }
        if let full = fullLabel, !full.isEmpty {
            return CatalogDegreeTypeFilter.requirementsStorageKey(fromProfileDegreeType: full)
        }
        return "Unknown"
    }
}

/// Universal translation gateway: any degree string → canonical form.
enum DegreeTypeNormalizer {
    /// Accepts any format and returns canonical form, or nil if unrecognizable.
    static func normalize(_ raw: String, allowSuffixPositionOnlyTokens: Bool = true) -> CanonicalDegreeType? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Already canonical full label
        if let entry = DegreeTokenRegistry.entry(matchingFullLabel: trimmed) {
            return canonical(from: entry, isConfirmed: true)
        }

        let collapsed = collapseForPhraseMatch(trimmed)

        // Step 2: whole-string token (BS, MS, M.S. after normalize)
        let wholeToken = DegreeTokenRegistry.normalizeToken(trimmed)
        if let entry = DegreeTokenRegistry.entry(forNormalizedToken: wholeToken, allowSuffixPositionOnly: allowSuffixPositionOnlyTokens) {
            return canonical(from: entry, isConfirmed: true)
        }

        // Step 3: parenthetical extraction — "Master of Science (MS)"
        if let open = trimmed.firstIndex(of: "("),
           let close = trimmed.lastIndex(of: ")"),
           open < close {
            let inner = String(trimmed[trimmed.index(after: open)..<close])
            for part in inner.split(whereSeparator: { "/,+;&".contains($0) }) {
                let token = DegreeTokenRegistry.normalizeToken(String(part))
                if let entry = DegreeTokenRegistry.entry(forNormalizedToken: token, allowSuffixPositionOnly: allowSuffixPositionOnlyTokens) {
                    return canonical(from: entry, isConfirmed: true)
                }
            }
        }

        // Step 4: first word — "M.S. in Computer Science", "MBA Finance"
        let parts = trimmed.split(separator: " ")
        if let first = parts.first {
            let firstToken = DegreeTokenRegistry.normalizeToken(String(first))
            if let entry = DegreeTokenRegistry.entry(forNormalizedToken: firstToken, allowSuffixPositionOnly: allowSuffixPositionOnlyTokens) {
                return canonical(from: entry, isConfirmed: true)
            }
        }

        // Step 5: phrase prefix match
        if let token = DegreeTokenRegistry.tokenFromPhrasePrefix(collapsed),
           let entry = DegreeTokenRegistry.entry(forNormalizedToken: token) {
            return canonical(from: entry, isConfirmed: true)
        }

        // Step 6: prefix heuristic (level only)
        if let level = levelFromPrefixHeuristic(collapsed) {
            return CanonicalDegreeType(
                token: nil,
                fullLabel: nil,
                displayLabel: "",
                degreeLevel: level,
                isConfirmed: false
            )
        }

        return nil
    }

    /// Maps catalog section bucket titles to canonical degree level (wraps ModernCampusCatalogLabels).
    static func levelHint(fromCatalogSection section: String) -> String? {
        let trimmed = section.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let normalized = ModernCampusCatalogLabels.normalizedCatalogTypeLabel(from: trimmed, catoid: "")
        guard !normalized.isEmpty, !normalized.hasPrefix("Catalog ") else { return nil }
        return DegreeConfiguration.canonicalLevel(normalized)
    }

    /// Partial result when only catalog section level is known.
    static func partialFromCatalogSection(_ section: String) -> CanonicalDegreeType? {
        guard let level = levelHint(fromCatalogSection: section) else { return nil }
        return CanonicalDegreeType(
            token: nil,
            fullLabel: nil,
            displayLabel: "",
            degreeLevel: level,
            isConfirmed: false
        )
    }

    /// Strips period-separated abbreviations for token regex (M.S. → MS).
    static func stripPeriodsFromAbbreviations(_ text: String) -> String {
        var result = text
        result = result.replacingOccurrences(
            of: #"\b([A-Za-z])\.([A-Za-z])\.([A-Za-z])\."#,
            with: "$1$2$3",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"\b([A-Za-z])\.([A-Za-z])\."#,
            with: "$1$2",
            options: .regularExpression
        )
        return result
    }

    private static func canonical(from entry: DegreeTokenRegistry.Entry, isConfirmed: Bool) -> CanonicalDegreeType {
        CanonicalDegreeType(
            token: entry.token,
            fullLabel: entry.fullLabel,
            displayLabel: entry.displayLabel,
            degreeLevel: entry.degreeLevel,
            isConfirmed: isConfirmed
        )
    }

    private static func collapseForPhraseMatch(_ raw: String) -> String {
        raw.uppercased()
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: " ", with: "")
    }

    private static func levelFromPrefixHeuristic(_ collapsed: String) -> String? {
        if collapsed.hasPrefix("BACHELOR") || collapsed.hasPrefix("ASSOCIATE") {
            return DegreeConfiguration.undergraduate
        }
        if collapsed.hasPrefix("MASTER") {
            return DegreeConfiguration.graduate
        }
        if collapsed.hasPrefix("JURIS") || collapsed.contains("JURIDICAL") {
            return DegreeConfiguration.lawSchool
        }
        if collapsed.contains("DENTAL") {
            return DegreeConfiguration.dentalSchool
        }
        if collapsed.hasPrefix("DOCTOR") || collapsed.contains("PHD") {
            if collapsed.contains("MEDICINE") && !collapsed.contains("EDUCATION") {
                return DegreeConfiguration.medicalSchool
            }
            return DegreeConfiguration.doctorateProfessional
        }
        return nil
    }
}
