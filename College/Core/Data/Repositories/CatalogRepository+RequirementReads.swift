// CatalogRepository+RequirementReads.swift
// Feature: Core/Data
// Purpose: Core/Data persistence — — CatalogRepository+RequirementReads.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftData

extension CatalogRepository {
    func fetchDegreeRequirements(
        universityID: UUID,
        programURL: String,
        degreeType: String
    ) throws -> [CatalogDegreeRequirement] {
        let canonicalURL = AcademicProgramHelpers.canonicalizeAcalogURL(programURL)
        guard !canonicalURL.isEmpty else { return [] }

        func fetch(matchingDegreeTypes candidates: [String]?) throws -> [CatalogDegreeRequirement] {
            if let candidates, !candidates.isEmpty {
                var all: [CatalogDegreeRequirement] = []
                for candidate in candidates {
                    var descriptor = FetchDescriptor<CatalogDegreeRequirement>(
                        predicate: #Predicate { row in
                            row.university?.id == universityID
                                && row.programURL == canonicalURL
                                && row.degreeType == candidate
                        },
                        sortBy: [
                            SortDescriptor(\.sectionOrder, order: .forward),
                            SortDescriptor(\.requirementCategory, order: .forward),
                        ]
                    )
                    descriptor.fetchLimit = 5_000
                    all.append(contentsOf: try context.fetch(descriptor))
                }
                if !all.isEmpty {
                    return dedupeRequirements(all)
                }
            }

            var descriptor = FetchDescriptor<CatalogDegreeRequirement>(
                predicate: #Predicate { row in
                    row.university?.id == universityID && row.programURL == canonicalURL
                },
                sortBy: [
                    SortDescriptor(\.sectionOrder, order: .forward),
                    SortDescriptor(\.requirementCategory, order: .forward),
                ]
            )
            descriptor.fetchLimit = 5_000
            return try context.fetch(descriptor)
        }

        let trimmedDegreeType = degreeType.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedDegreeType.isEmpty {
            let exact = try fetch(matchingDegreeTypes: [trimmedDegreeType])
            if !exact.isEmpty { return exact }
        }

        var candidates = AcademicProgramHelpers.degreeTypeCandidates(from: trimmedDegreeType)
        if !trimmedDegreeType.isEmpty, !candidates.contains(trimmedDegreeType) {
            candidates.insert(trimmedDegreeType, at: 0)
        }
        if !candidates.isEmpty {
            let tolerant = try fetch(matchingDegreeTypes: candidates)
            if !tolerant.isEmpty { return tolerant }
        }
        return try fetch(matchingDegreeTypes: nil)
    }

    func fetchDegreeRequirementsForMajor(
        universityID: UUID,
        majorDisplay: String,
        degreeType: String?,
        degreeLevel: String?
    ) throws -> [CatalogDegreeRequirement] {
        let cleaned = AcademicProgramHelpers.cleanedProgramNameFromDisplay(
            majorDisplay,
            profileDegreeType: degreeType
        )
        let majorKey = cleaned.isEmpty
            ? majorDisplay.trimmingCharacters(in: .whitespacesAndNewlines)
            : cleaned
        guard !majorKey.isEmpty else { return [] }

        let candidates = AcademicProgramHelpers.mergedDegreeTypeCandidates(
            majorDisplay: majorDisplay,
            profileDegreeType: degreeType
        )

        func fetch(matchingDegreeTypes types: [String]?) throws -> [CatalogDegreeRequirement] {
            if let types, !types.isEmpty {
                var combined: [CatalogDegreeRequirement] = []
                for type in types {
                    var descriptor = FetchDescriptor<CatalogDegreeRequirement>(
                        predicate: #Predicate { row in
                            row.university?.id == universityID
                                && row.major == majorKey
                                && row.degreeType == type
                        },
                        sortBy: [
                            SortDescriptor(\.sectionOrder, order: .forward),
                            SortDescriptor(\.requirementCategory, order: .forward),
                        ]
                    )
                    descriptor.fetchLimit = 5_000
                    combined.append(contentsOf: try context.fetch(descriptor))
                }
                if !combined.isEmpty {
                    return dedupeRequirements(combined)
                }
            }

            var descriptor = FetchDescriptor<CatalogDegreeRequirement>(
                predicate: #Predicate { row in
                    row.university?.id == universityID && row.major == majorKey
                },
                sortBy: [
                    SortDescriptor(\.sectionOrder, order: .forward),
                    SortDescriptor(\.requirementCategory, order: .forward),
                ]
            )
            descriptor.fetchLimit = 5_000
            return try context.fetch(descriptor)
        }

        if !candidates.isEmpty {
            let exactish = try fetch(matchingDegreeTypes: candidates)
            if !exactish.isEmpty { return exactish }
        }
        _ = degreeLevel
        return try fetch(matchingDegreeTypes: nil)
    }

    func fetchDegreeRequirementsByName(
        universityID: UUID,
        name: String,
        requireDegreeType: String? = nil,
        excludeDegreeTypes: [String] = []
    ) throws -> [CatalogDegreeRequirement] {
        var results = try fetchDegreeRequirementsForMajor(
            universityID: universityID,
            majorDisplay: name,
            degreeType: requireDegreeType,
            degreeLevel: nil
        )
        if results.isEmpty {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return [] }
            var descriptor = FetchDescriptor<CatalogDegreeRequirement>(
                predicate: #Predicate { row in
                    row.university?.id == universityID && row.major == trimmed
                },
                sortBy: [
                    SortDescriptor(\.sectionOrder, order: .forward),
                    SortDescriptor(\.requirementCategory, order: .forward),
                ]
            )
            descriptor.fetchLimit = 5_000
            results = try context.fetch(descriptor)
        }

        if let required = requireDegreeType?.trimmingCharacters(in: .whitespacesAndNewlines), !required.isEmpty {
            results = results.filter { $0.degreeType.caseInsensitiveCompare(required) == .orderedSame }
        }
        for excluded in excludeDegreeTypes {
            let token = excluded.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !token.isEmpty else { continue }
            results = results.filter { $0.degreeType.caseInsensitiveCompare(token) != .orderedSame }
        }
        return results
    }

    func schoolForDepartment(universityID: UUID, departmentName: String) throws -> String? {
        let normalizedInput = normalizeDepartmentKey(departmentName)
        guard !normalizedInput.isEmpty else { return nil }

        let departments = try fetchDepartments(universityID: universityID, limit: 2_000)
        let matches = departments.filter { dept in
            let name = dept.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return false }
            let normalizedName = normalizeDepartmentKey(name)
            return normalizedName == normalizedInput
                || normalizedName.contains(normalizedInput)
                || normalizedInput.contains(normalizedName)
        }

        let best = matches.first { dept in
            let school = (dept.school ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return !school.isEmpty
        } ?? matches.first

        let school = (best?.school ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return school.isEmpty ? nil : school
    }

    func resolveMajor(
        universityID: UUID,
        display: String,
        degreeLevel: String?,
        degreeType: String?,
        isMinor: Bool = false
    ) throws -> Major? {
        let raw = display.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }

        let cleanedName = AcademicProgramHelpers.cleanedProgramNameFromDisplay(
            raw,
            profileDegreeType: degreeType
        )
        let level = (degreeLevel ?? "Undergraduate").trimmingCharacters(in: .whitespacesAndNewlines)
        let degreeCandidates = AcademicProgramHelpers.degreeTypeCandidates(from: degreeType ?? "")

        var descriptor = FetchDescriptor<Major>(
            predicate: #Predicate { major in
                major.university?.id == universityID
                    && major.isMinor == isMinor
                    && major.degreeLevel == level
                    && major.name == cleanedName
            }
        )
        descriptor.fetchLimit = 20
        let results = try context.fetch(descriptor)

        if results.count == 1 { return results.first }
        if results.count > 1, !degreeCandidates.isEmpty {
            if let match = results.first(where: { entity in
                let stored = (entity.degreeType ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                return degreeCandidates.contains(where: { $0.caseInsensitiveCompare(stored) == .orderedSame })
            }) {
                return match
            }
        }
        return results.first
    }

    func resolveProgramURL(
        universityID: UUID,
        programDisplay: String,
        degreeLevel: String?,
        degreeType: String?,
        isMinor: Bool
    ) throws -> String? {
        guard let major = try resolveMajor(
            universityID: universityID,
            display: programDisplay,
            degreeLevel: degreeLevel,
            degreeType: degreeType,
            isMinor: isMinor
        ) else { return nil }
        let url = (major.programURL ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { return nil }
        return AcademicProgramHelpers.canonicalizeAcalogURL(url)
    }

    func fetchCourseOverride(universityID: UUID, courseCode: String) throws -> CourseOverride? {
        let needle = courseCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return nil }
        var descriptor = FetchDescriptor<CourseOverride>(
            predicate: #Predicate { row in
                row.university?.id == universityID && row.courseCode == needle
            }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    func fetchCompletedCourseOverrides(universityID: UUID, limit: Int = 500) throws -> [CourseOverride] {
        var descriptor = FetchDescriptor<CourseOverride>(
            predicate: #Predicate { row in
                row.university?.id == universityID && row.status == "Completed"
            }
        )
        descriptor.fetchLimit = max(1, limit)
        return try context.fetch(descriptor)
    }

    func upsertCourseOverride(
        universityID: UUID,
        courseCode: String,
        courseName: String?,
        credits: Double?,
        professor: String?,
        semesterText: String?,
        status: String,
        grade: String?,
        gradingType: String,
        externalURL: String?
    ) throws -> CourseOverride {
        let normalizedCode = courseCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedCode.isEmpty else {
            throw NSError(domain: "CatalogRepository", code: 1, userInfo: [NSLocalizedDescriptionKey: "Empty course code"])
        }

        let override: CourseOverride
        if let existing = try fetchCourseOverride(universityID: universityID, courseCode: normalizedCode) {
            override = existing
        } else {
            override = CourseOverride(courseCode: normalizedCode)
            override.university = try fetchUniversity(id: universityID)
            context.insert(override)
        }

        if let courseName {
            override.courseName = courseName.trimmingCharacters(in: .whitespacesAndNewlines)
        } else if override.courseName == nil {
            override.courseName = ""
        }
        if let credits {
            override.credits = credits
        } else if override.credits == nil {
            override.credits = 0
        }
        override.professor = professor?.trimmingCharacters(in: .whitespacesAndNewlines)
        override.semesterText = semesterText?.trimmingCharacters(in: .whitespacesAndNewlines)
        override.status = status.trimmingCharacters(in: .whitespacesAndNewlines)
        override.grade = grade?.trimmingCharacters(in: .whitespacesAndNewlines)
        override.gradingType = gradingType.trimmingCharacters(in: .whitespacesAndNewlines)
        override.externalURL = externalURL?.trimmingCharacters(in: .whitespacesAndNewlines)
        override.lastUpdated = .now
        ModelMergeCoalescer.scheduleSave(context)
        return override
    }

    private func dedupeRequirements(_ rows: [CatalogDegreeRequirement]) -> [CatalogDegreeRequirement] {
        var seen = Set<UUID>()
        var out: [CatalogDegreeRequirement] = []
        for row in rows {
            guard seen.insert(row.id).inserted else { continue }
            out.append(row)
        }
        return out.sorted {
            if $0.sectionOrder != $1.sectionOrder { return $0.sectionOrder < $1.sectionOrder }
            return $0.requirementCategory.localizedCaseInsensitiveCompare($1.requirementCategory) == .orderedAscending
        }
    }

    private func normalizeDepartmentKey(_ value: String) -> String {
        var s = value.normalizedCatalogText().lowercased()
        if s.hasPrefix("department of ") {
            s = String(s.dropFirst("department of ".count))
        }
        let removeList = [" department page", " department", " program", " office", " page"]
        for term in removeList where s.hasSuffix(term) {
            s = String(s.dropLast(term.count))
        }
        s = s.replacingOccurrences(of: "&", with: "and")
        return s.normalizedCatalogText()
    }
}