// CatalogProgramWriteBridge.swift
// Feature: Catalog
// Purpose: Catalog module — CatalogProgramWriteBridge.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftData

/// local store-only catalog program/department writes (Phase 7f).
@MainActor
enum CatalogProgramWriteBridge {
    typealias DepartmentInput = (name: String, code: String?, school: String?)
    typealias ProgramInput = (
        name: String,
        degreeLevel: String,
        degreeType: String?,
        isMinor: Bool,
        department: String?,
        url: String?,
        resolvedDepartment: String?,
        resolvedCollege: String?,
        mappingConfidence: Double?,
        mappingSource: String?,
        requirements: [DegreeRequirement]?,
        trackVariant: String?,
        parentProgramKey: String?
    )
    typealias ProgramInputWithCatalog = (
        name: String,
        degreeLevel: String,
        degreeType: String?,
        isMinor: Bool,
        department: String?,
        url: String?,
        resolvedDepartment: String?,
        resolvedCollege: String?,
        mappingConfidence: Double?,
        mappingSource: String?,
        requirements: [DegreeRequirement]?,
        sourceCatalogCatoid: String?,
        trackVariant: String?,
        parentProgramKey: String?
    )

    static func saveDepartments(
        _ departments: [DepartmentInput],
        for universityName: String,
        appDataStore: AppDataStore = .shared
    ) throws {
        guard let (repo, universityID) = alignedRepository(
            universityName: universityName,
            appDataStore: appDataStore
        ) else { return }

        let inputs = departments.map { dept in
            CatalogRepository.DepartmentUpsertInput(
                id: UUID(),
                name: dept.name,
                code: dept.code,
                school: dept.school
            )
        }
        try repo.upsertDepartments(universityID: universityID, inputs: inputs)
        ModelMergeCoalescer.flushNow()
        appDataStore.bumpCatalogDataRevision()
    }

    static func savePrograms(
        _ majors: [ProgramInput],
        for universityName: String,
        pruneStalePrograms: Bool = true,
        appDataStore: AppDataStore = .shared
    ) throws {
        let withCatalog: [ProgramInputWithCatalog] = majors.map {
            (
                name: $0.name,
                degreeLevel: $0.degreeLevel,
                degreeType: $0.degreeType,
                isMinor: $0.isMinor,
                department: $0.department,
                url: $0.url,
                resolvedDepartment: $0.resolvedDepartment,
                resolvedCollege: $0.resolvedCollege,
                mappingConfidence: $0.mappingConfidence,
                mappingSource: $0.mappingSource,
                requirements: $0.requirements,
                sourceCatalogCatoid: nil,
                trackVariant: $0.trackVariant,
                parentProgramKey: $0.parentProgramKey
            )
        }
        try savePrograms(withCatalog, for: universityName, pruneStalePrograms: pruneStalePrograms, appDataStore: appDataStore)
    }

    static func savePrograms(
        _ majors: [ProgramInputWithCatalog],
        for universityName: String,
        pruneStalePrograms: Bool = true,
        appDataStore: AppDataStore = .shared
    ) throws {
        _ = pruneStalePrograms
        guard let (repo, universityID) = alignedRepository(
            universityName: universityName,
            appDataStore: appDataStore
        ) else { return }

        let departmentLookup = try repo.departmentLookup(universityID: universityID)
        let inputs: [CatalogRepository.MajorUpsertInput] = majors.map { major in
            let departmentName = (major.resolvedDepartment ?? major.department ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let departmentID = departmentName.isEmpty
                ? nil
                : departmentLookup[departmentName.lowercased()]?.id
            return CatalogRepository.MajorUpsertInput(
                id: UUID(),
                name: major.name,
                degreeLevel: major.degreeLevel,
                degreeType: major.degreeType,
                isMinor: major.isMinor,
                programURL: major.url,
                programURLs: nil,
                sourceCatoids: major.sourceCatalogCatoid,
                resolvedDepartment: major.resolvedDepartment,
                resolvedCollege: major.resolvedCollege,
                departmentIDs: departmentID.map { [$0] } ?? []
            )
        }
        try repo.upsertMajors(universityID: universityID, inputs: inputs)
        ModelMergeCoalescer.flushNow()
        appDataStore.bumpCatalogDataRevision()
    }

    static func finishChunkedProgramsPrune(
        _ majors: [ProgramInputWithCatalog],
        for universityName: String,
        appDataStore: AppDataStore = .shared
    ) throws {
        _ = majors
        _ = universityName
        _ = appDataStore
    }

    private static func alignedRepository(
        universityName: String,
        appDataStore: AppDataStore
    ) -> (CatalogRepository, UUID)? {
        guard let repo = appDataStore.catalogRepository else { return nil }
        let trimmed = universityName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let active = try? repo.fetchActiveUniversity(),
              active.name.caseInsensitiveCompare(trimmed) == .orderedSame else {
            return nil
        }
        return (repo, active.id)
    }
}
