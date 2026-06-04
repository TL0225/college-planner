// CatalogProgramReadBridge.swift
// Feature: Catalog
// Purpose: Catalog module — CatalogProgramReadBridge.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftData

/// local store-only catalog program label reads (Phase 7f — no local store fallback).
@MainActor
enum CatalogProgramReadBridge {
    static func fetchMajors(
        for universityName: String,
        degreeLevel: String,
        department: String? = nil,
        degreeType: String? = nil,
        includeMinors: Bool = false,
        sourceCatoid: String? = nil,
        appDataStore: AppDataStore = .shared
    ) -> [String] {
        storeLabels(
            for: universityName,
            degreeLevel: degreeLevel,
            department: department,
            degreeType: degreeType,
            includeMinors: includeMinors,
            sourceCatoid: sourceCatoid,
            appDataStore: appDataStore
        )
    }

    static func fetchMinors(
        for universityName: String,
        degreeLevel: String,
        sourceCatoid: String? = nil,
        appDataStore: AppDataStore = .shared
    ) -> [String] {
        let undergrad = fetchMajors(
            for: universityName,
            degreeLevel: "Undergraduate",
            department: nil,
            degreeType: nil,
            includeMinors: true,
            sourceCatoid: sourceCatoid,
            appDataStore: appDataStore
        )
        let legacy = fetchMajors(
            for: universityName,
            degreeLevel: "Minor",
            department: nil,
            degreeType: nil,
            includeMinors: true,
            sourceCatoid: sourceCatoid,
            appDataStore: appDataStore
        )
        return Array(Set(undergrad + legacy)).sorted()
    }

    private static func storeLabels(
        for universityName: String,
        degreeLevel: String,
        department: String?,
        degreeType: String?,
        includeMinors: Bool,
        sourceCatoid: String?,
        appDataStore: AppDataStore
    ) -> [String] {
        guard let (repo, universityID) = alignedCatalogRepository(
            universityName: universityName,
            appDataStore: appDataStore
        ) else {
            return []
        }
        guard (try? repo.hasPrograms(universityID: universityID)) == true else {
            return []
        }

        guard let majors = try? repo.fetchAllMajors(universityID: universityID) else {
            return []
        }

        let filtered = majors.filter { major in
            guard major.degreeLevel == degreeLevel, major.isMinor == includeMinors else {
                return false
            }
            if !matchesDepartment(major, department: department) {
                return false
            }
            if !matchesDegreeType(major, degreeType: degreeType, includeMinors: includeMinors) {
                return false
            }
            if !matchesCatoid(major, targetCatoid: sourceCatoid) {
                return false
            }
            return true
        }

        return displayLabels(for: filtered, includeMinors: includeMinors)
    }

    private static func alignedCatalogRepository(
        universityName: String,
        appDataStore: AppDataStore
    ) -> (CatalogRepository, UUID)? {
        guard let repo = appDataStore.catalogRepository else { return nil }
        let trimmedName = universityName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return nil }
        guard let active = try? repo.fetchActiveUniversity(),
              active.name.caseInsensitiveCompare(trimmedName) == .orderedSame else {
            return nil
        }
        return (repo, active.id)
    }

    private static func matchesDepartment(_ major: Major, department: String?) -> Bool {
        guard let dept = department?.trimmingCharacters(in: .whitespacesAndNewlines), !dept.isEmpty else {
            return true
        }

        let normalizedDept = CatalogProgramMatching.normalizeProgramDepartmentKey(dept)
        let stopwords: Set<String> = ["and", "of", "the", "for", "in", "to", "on", "at", "a", "an"]
        let deptTokens = normalizedDept
            .split(separator: " ")
            .map { String($0) }
            .filter { token in
                let t = token.trimmingCharacters(in: .whitespacesAndNewlines)
                if t.count < 3 { return false }
                return !stopwords.contains(t)
            }

        func fieldMatches(_ value: String?) -> Bool {
            guard let value else { return false }
            let candidate = CatalogProgramMatching.normalizeProgramDepartmentKey(value)
            if candidate == normalizedDept { return true }
            if value.caseInsensitiveCompare(dept) == .orderedSame { return true }
            if candidate.localizedCaseInsensitiveContains(normalizedDept) { return true }
            return CatalogProgramMatching.programDepartmentKeysMatch(normalizedDept, candidate: candidate)
        }

        if fieldMatches(major.resolvedDepartment) || fieldMatches(major.resolvedCollege) {
            return true
        }

        let linkedDepartments = major.departments ?? []
        for linked in linkedDepartments {
            if fieldMatches(linked.name) || fieldMatches(linked.code) || fieldMatches(linked.school) {
                return true
            }
        }

        if !deptTokens.isEmpty {
            let searchable = [major.resolvedDepartment, major.resolvedCollege]
                + linkedDepartments.flatMap { [$0.name, $0.code, $0.school] }
            let normalizedSearchable = searchable
                .compactMap { $0 }
                .map { CatalogProgramMatching.normalizeProgramDepartmentKey($0) }
            return deptTokens.allSatisfy { token in
                normalizedSearchable.contains { field in
                    field.localizedCaseInsensitiveContains(token)
                }
            }
        }

        return false
    }

    private static func matchesDegreeType(
        _ major: Major,
        degreeType: String?,
        includeMinors: Bool
    ) -> Bool {
        guard !includeMinors else { return true }
        guard let raw = degreeType?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return true
        }

        let candidates = CatalogProgramMatching.degreeTypeCandidates(from: raw)
        guard !candidates.isEmpty else { return true }
        let stored = (major.degreeType ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stored.isEmpty else { return false }

        return candidates.contains { candidate in
            stored.compare(candidate, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
    }

    private static func matchesCatoid(_ major: Major, targetCatoid: String?) -> Bool {
        let token = (targetCatoid ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return true }

        if catoidTokenSet(fromCSV: major.sourceCatoids).contains(token) {
            return true
        }
        if catoidToken(fromURLString: major.programURL)
            .compare(token, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame {
            return true
        }
        if catoidTokenSet(fromCSV: major.programURLs).contains(token) {
            return true
        }

        let urlCandidates = [major.programURL, major.programURLs]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        for raw in urlCandidates {
            for part in raw.split(separator: ",") {
                let urlString = String(part).trimmingCharacters(in: .whitespacesAndNewlines)
                if CourseLeafCatalogSegmentDiscoverer.programURLMatchesCatalogID(urlString, catalogID: token) {
                    return true
                }
            }
        }
        return false
    }

    private static func catoidToken(fromURLString rawURL: String?) -> String {
        let raw = (rawURL ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, let comps = URLComponents(string: raw) else { return "" }
        return comps.queryItems?
            .first(where: {
                $0.name.compare("catoid", options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            })?
            .value?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func catoidTokenSet(fromCSV raw: String?) -> Set<String> {
        let value = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return [] }
        return Set(
            value
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
    }

    private static func displayLabels(for majors: [Major], includeMinors: Bool) -> [String] {
        var uniqueMajors = Set<String>()
        for major in majors {
            let name = major.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }

            if !includeMinors, let degreeType = major.degreeType, !degreeType.isEmpty {
                var trimmedName = name
                trimmedName = trimmedName
                    .replacingOccurrences(of: ",\\s*$", with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmedName.contains("/") {
                    uniqueMajors.insert(trimmedName)
                    continue
                }
                uniqueMajors.insert(
                    ProgramListSerialization.displayLabel(programName: trimmedName, degreeType: degreeType)
                )
            } else {
                uniqueMajors.insert(name)
            }
        }
        return Array(uniqueMajors).sorted()
    }
}
