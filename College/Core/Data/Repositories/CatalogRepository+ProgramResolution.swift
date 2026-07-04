// CatalogRepository+ProgramResolution.swift
// Feature: Core/Data
// Purpose: Core/Data persistence — — RequirementsRefreshResult.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftData

extension CatalogRepository {
    struct RequirementsRefreshResult: Sendable {
        let programURL: String
        let skippedDueToFreshCache: Bool
        let savedRowCount: Int
        let savedCourseCount: Int
        let errorMessage: String?
    }

    func resolveProgramURL(
        programDisplay: String,
        universityName: String,
        degreeLevel: String,
        degreeType: String?,
        isMinor: Bool,
        ownershipHint: String? = nil
    ) throws -> String? {
        guard let university = try fetchUniversity(named: universityName) else { return nil }

        let target = programDisplay.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else { return nil }

        let cleanedName = CatalogProgramNameHelpers.cleanedProgramName(from: target, degreeType: degreeType)
        let level = degreeLevel.trimmingCharacters(in: .whitespacesAndNewlines)
        let degreeCandidates = CatalogProgramNameHelpers.mergedDegreeTypeCandidates(
            majorDisplay: target,
            profileDegreeType: degreeType
        )

        var results = try fetchMajors(
            universityID: university.id,
            name: cleanedName,
            degreeLevel: level.isEmpty ? nil : level,
            isMinor: isMinor
        )

        if results.isEmpty, cleanedName != target {
            results = try fetchMajors(
                universityID: university.id,
                name: target,
                degreeLevel: level.isEmpty ? nil : level,
                isMinor: isMinor
            )
        }

        // Degree-level fallback: older/stale stores may hold catalog-title-style levels
        // (e.g. "Graduate Catalog 2025-2026") that don't equal the profile's "Graduate".
        // Retry name-only so already-scraped programs still resolve without a re-scrape.
        if results.isEmpty {
            results = try fetchMajors(
                universityID: university.id,
                name: cleanedName,
                degreeLevel: nil,
                isMinor: isMinor
            )
            if results.isEmpty, cleanedName != target {
                results = try fetchMajors(
                    universityID: university.id,
                    name: target,
                    degreeLevel: nil,
                    isMinor: isMinor
                )
            }
        }

        if results.count > 1, !degreeCandidates.isEmpty {
            let degreeMatches = results.filter { major in
                let stored = (major.degreeType ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                return degreeCandidates.contains(where: { $0.caseInsensitiveCompare(stored) == .orderedSame })
            }
            if !degreeMatches.isEmpty { results = degreeMatches }
        }

        let hint = (ownershipHint ?? CatalogProgramNameHelpers.ownershipHint(for: target))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let major = disambiguateMajors(results, ownershipHint: hint) ?? results.first
        guard let url = major?.programURL?.trimmingCharacters(in: .whitespacesAndNewlines), !url.isEmpty else {
            return nil
        }
        return CatalogProgramNameHelpers.canonicalizeAcalogURL(url, removingQueryItems: ["returnto"])
    }

    private func fetchMajors(
        universityID: UUID,
        name: String,
        degreeLevel: String?,
        isMinor: Bool
    ) throws -> [Major] {
        let all = try fetchAllMajors(universityID: universityID)
        return all.filter { major in
            guard major.name.caseInsensitiveCompare(name) == .orderedSame,
                  major.isMinor == isMinor else { return false }
            if let degreeLevel, !degreeLevel.isEmpty {
                return Self.degreeLevelsMatch(stored: major.degreeLevel, requested: degreeLevel)
            }
            return true
        }
    }

    /// Tolerant degree-level comparison. Treats catalog-title-style stored values
    /// ("Graduate Catalog 2025-2026") as equal to the canonical level ("Graduate"),
    /// so link resolution survives stale stores and catalog labelling variants.
    static func degreeLevelsMatch(stored: String, requested: String) -> Bool {
        let r = requested.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !r.isEmpty else { return true }
        let s = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.caseInsensitiveCompare(r) == .orderedSame { return true }
        let sNorm = ModernCampusCatalogLabels.normalizedCatalogTypeLabel(from: s, catoid: "")
        let rNorm = ModernCampusCatalogLabels.normalizedCatalogTypeLabel(from: r, catoid: "")
        return sNorm.caseInsensitiveCompare(rNorm) == .orderedSame
    }

    private func disambiguateMajors(_ majors: [Major], ownershipHint: String?) -> Major? {
        guard !majors.isEmpty else { return nil }
        if majors.count == 1 { return majors.first }
        let hint = ownershipHint?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        guard !hint.isEmpty else { return majors.first }
        let hinted = majors.filter { major in
            let college = (major.resolvedCollege ?? "").lowercased()
            let department = (major.resolvedDepartment ?? "").lowercased()
            return college.contains(hint) || department.contains(hint) || hint.contains(college)
        }
        return hinted.first ?? majors.first
    }
}

enum CatalogProgramNameHelpers {
    static func cleanedProgramName(from display: String, degreeType: String?) -> String {
        let trimmed = display.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return trimmed }
        if let comma = trimmed.lastIndex(of: ",") {
            let suffix = trimmed[trimmed.index(after: comma)...].trimmingCharacters(in: .whitespacesAndNewlines)
            if suffix.count <= 8, suffix.range(of: "^[A-Za-z.]+$", options: .regularExpression) != nil {
                return String(trimmed[..<comma]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return trimmed
        }
        let candidates = mergedDegreeTypeCandidates(majorDisplay: trimmed, profileDegreeType: degreeType)
        guard !candidates.isEmpty else { return trimmed }
        let parts = trimmed.split(separator: " ")
        guard parts.count >= 2 else { return trimmed }
        let last = String(parts.last ?? "")
        guard last.count <= 8, last.range(of: "^[A-Za-z.]+$", options: .regularExpression) != nil else {
            return trimmed
        }
        let lastNorm = last.uppercased().replacingOccurrences(of: ".", with: "")
        if candidates.contains(where: {
            $0.uppercased().replacingOccurrences(of: ".", with: "") == lastNorm
        }) {
            return parts.dropLast().joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed
    }

    static func mergedDegreeTypeCandidates(majorDisplay: String, profileDegreeType: String?) -> [String] {
        var candidates: [String] = []
        if let profileDegreeType {
            let trimmed = profileDegreeType.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { candidates.append(trimmed) }
        }
        if let open = majorDisplay.firstIndex(of: "("),
           let close = majorDisplay.lastIndex(of: ")"),
           open < close {
            let inner = String(majorDisplay[majorDisplay.index(after: open)..<close])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !inner.isEmpty { candidates.append(inner) }
        }
        var seen: Set<String> = []
        return candidates.filter { seen.insert($0.lowercased()).inserted }
    }

    static func ownershipHint(for majorDisplay: String) -> String? {
        let trimmed = majorDisplay.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let open = trimmed.lastIndex(of: "("), let close = trimmed.lastIndex(of: ")"), open < close {
            let inner = String(trimmed[trimmed.index(after: open)..<close])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !inner.isEmpty { return inner }
        }
        if trimmed.localizedCaseInsensitiveContains("tandon") { return "Tandon" }
        if trimmed.localizedCaseInsensitiveContains("steinhardt") { return "Steinhardt" }
        return nil
    }

    static func canonicalizeAcalogURL(_ urlString: String, removingQueryItems: Set<String>) -> String {
        let cleaned = urlString
            .replacingOccurrences(of: "\u{00A0}", with: "")
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return "" }
        guard var components = URLComponents(string: cleaned) else { return cleaned }
        if !removingQueryItems.isEmpty, var items = components.queryItems {
            items.removeAll { removingQueryItems.contains($0.name.lowercased()) }
            components.queryItems = items.isEmpty ? nil : items
        }
        return components.string ?? cleaned
    }
}