// CatalogProgramPickerBridge.swift
// Feature: Catalog
// Purpose: Catalog module — CatalogProgramPickerRowSnapshot.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftData

/// Resolved university target for off-main catalog program fetches.
struct CatalogProgramPickerUniversityTarget: Sendable {
    let universityID: UUID
    let displayName: String
}

/// Sendable catalog program row for off-main requirements picker builds (Phase 5 P0).
struct CatalogProgramPickerRowSnapshot: Sendable {
    let universityName: String
    let name: String
    let degreeLevel: String
    let degreeType: String?
    let isMinor: Bool
    let programURL: String?
    let resolvedDepartment: String?
    let resolvedCollege: String?
    let departmentSchool: String?
    let departmentName: String?
}

/// Background-safe catalog program fetches for the requirements picker (Phase 5 P0).
enum CatalogProgramPickerQuery {
    static let majorsPerUniversityLimit = 5_000

    static func fetchRows(
        universityTargets: [CatalogProgramPickerUniversityTarget],
        context: ModelContext
    ) throws -> [CatalogProgramPickerRowSnapshot] {
        let allowed = Set(
            universityTargets
                .map { $0.displayName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
        )
        guard !allowed.isEmpty else { return [] }

        var rows: [CatalogProgramPickerRowSnapshot] = []
        rows.reserveCapacity(min(allowed.count * 64, majorsPerUniversityLimit))

        for target in universityTargets {
            let majors = try fetchAllMajors(universityID: target.universityID, context: context)
            for major in majors {
                let universityName = (major.university?.name ?? target.displayName)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard allowed.contains(universityName.lowercased()) else { continue }

                let firstDepartment = major.departments?.first
                rows.append(
                    CatalogProgramPickerRowSnapshot(
                        universityName: universityName,
                        name: major.name.trimmingCharacters(in: .whitespacesAndNewlines),
                        degreeLevel: major.degreeLevel.trimmingCharacters(in: .whitespacesAndNewlines),
                        degreeType: major.degreeType?.trimmingCharacters(in: .whitespacesAndNewlines),
                        isMinor: major.isMinor,
                        programURL: major.programURL?.trimmingCharacters(in: .whitespacesAndNewlines),
                        resolvedDepartment: major.resolvedDepartment,
                        resolvedCollege: major.resolvedCollege,
                        departmentSchool: firstDepartment?.school,
                        departmentName: firstDepartment?.name
                    )
                )
            }
        }

        return rows.sorted { lhs, rhs in
            if lhs.universityName != rhs.universityName {
                return lhs.universityName.localizedCaseInsensitiveCompare(rhs.universityName) == .orderedAscending
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    static func pickerLabel(name: String, degreeType: String?, isMinor: Bool) -> String? {
        let rawName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawName.isEmpty else { return nil }
        if isMinor { return rawName }
        guard let degreeType = degreeType?.trimmingCharacters(in: .whitespacesAndNewlines), !degreeType.isEmpty else {
            return rawName
        }

        var trimmedName = rawName
            .replacingOccurrences(of: ",\\s*$", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        trimmedName = trimmedName.replacingOccurrences(
            of: #"\s*\([^)]+\)\s*$"#,
            with: "",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedName.contains("/") { return trimmedName }
        if trimmedName.hasSuffix("(\(degreeType))") { return trimmedName }
        return "\(trimmedName) (\(degreeType))"
    }

    static func sectionTitle(for row: CatalogProgramPickerRowSnapshot) -> String? {
        let level = row.degreeLevel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !level.isEmpty else { return nil }

        var bucket = ownershipLabel(row.resolvedCollege)
        if bucket.isEmpty { bucket = ownershipLabel(row.resolvedDepartment) }
        if bucket.isEmpty {
            let school = ownershipLabel(row.departmentSchool)
            let deptName = ownershipLabel(row.departmentName)
            bucket = school.isEmpty ? deptName : school
        }
        if bucket.isEmpty { return level }
        return "\(level) > \(bucket)"
    }

    private static func ownershipLabel(_ raw: String?) -> String {
        var value = (raw ?? "")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return "" }
        if value.hasPrefix("Department of ") {
            value = String(value.dropFirst("Department of ".count))
        }
        return value
    }

    private static func fetchAllMajors(universityID: UUID, context: ModelContext) throws -> [Major] {
        var descriptor = FetchDescriptor<Major>(
            predicate: #Predicate { major in
                major.university?.id == universityID
            },
            sortBy: [SortDescriptor(\.name, order: .forward)]
        )
        descriptor.fetchLimit = majorsPerUniversityLimit
        return try context.fetch(descriptor)
    }
}

/// Off-main catalog program picker reads (mirrors ``AuditCatalogLookupBridge``).
enum CatalogProgramPickerBridge {
    static func selectableProgramsOffMain(
        universityNames: [String]
    ) async -> [CatalogProgramRequirementsHydrator.SelectableProgram] {
        let prepared = await MainActor.run { () -> (ModelContainer, [CatalogProgramPickerUniversityTarget])? in
            let store = AppDataStore.shared
            var targets: [CatalogProgramPickerUniversityTarget] = []
            for rawName in universityNames {
                let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty,
                      let (repo, universityID) = CatalogStoreSnapshotBridge.catalogRepositoryForUniversity(
                        named: trimmed,
                        appDataStore: store,
                        activate: false
                      ) else { continue }
                let displayName = (try? repo.fetchUniversity(id: universityID))?.name ?? trimmed
                targets.append(
                    CatalogProgramPickerUniversityTarget(
                        universityID: universityID,
                        displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                )
            }
            guard !targets.isEmpty else { return nil }
            return (store.profileContainer, targets)
        }
        guard let (container, targets) = prepared else { return [] }

        let rows = await Task.detached(priority: .userInitiated) {
            let context = ModelContext(container)
            return (try? CatalogProgramPickerQuery.fetchRows(universityTargets: targets, context: context)) ?? []
        }.value

        return CatalogProgramRequirementsHydrator.selectablePrograms(fromPickerRows: rows)
    }
}
