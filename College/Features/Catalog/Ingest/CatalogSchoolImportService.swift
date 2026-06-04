// CatalogSchoolImportService.swift
// Feature: Catalog
// Purpose: Catalog module — ImportPolicy.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import os

/// local store-only school catalog import (Phase 7f — no local store).
@MainActor
enum CatalogSchoolImportService {
    struct ImportPolicy: Sendable {
        let archiveMissingCourses: Bool

        static let fullSnapshot = ImportPolicy(archiveMissingCourses: true)
        static let preserveExistingCourses = ImportPolicy(archiveMissingCourses: false)
    }

    static func importSchoolCatalog(
        _ schoolProfile: SchoolProfile,
        policy: ImportPolicy = .fullSnapshot,
        appDataStore: AppDataStore = .shared
    ) async throws {
        let log = OSLog(subsystem: Bundle.main.bundleIdentifier ?? "College", category: "CatalogImport")
        let signpostID = OSSignpostID(log: log)
        os_signpost(
            .begin,
            log: log,
            name: "ImportSchoolCatalog",
            signpostID: signpostID,
            "school=%{public}@ courses=%{public}d",
            schoolProfile.schoolName,
            schoolProfile.courses.count
        )
        defer {
            os_signpost(.end, log: log, name: "ImportSchoolCatalog", signpostID: signpostID)
        }

        storeSchoolPolicyMetadata(
            SchoolPolicyMetadataEnricher.metadata(profile: schoolProfile),
            universityID: nil,
            universityName: schoolProfile.schoolName
        )

        let schoolID = CatalogStoreCoordinator.shared.schoolID(for: schoolProfile.schoolName)
        try appDataStore.setActiveCatalogSchoolID(schoolID)
        guard let repo = appDataStore.catalogRepository else {
            throw NSError(
                domain: "CatalogImport",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Catalog local store container is not available."]
            )
        }

        let universityID = stableUniversityID(for: schoolProfile)
        let university = try repo.ensureUniversityForImport(
            id: universityID,
            name: schoolProfile.schoolName,
            catalogURL: schoolProfile.catalogURL
        )

        let departmentLookup = try repo.departmentLookup(universityID: university.id)
        let dedupedCourses = CatalogImportTransforms.deduplicatedCourses(schoolProfile.courses)
        let scrapedCodes = Set(dedupedCourses.map { CatalogImportTransforms.normalizeCourseCode($0.courseCode) })

        let chunkSize = 500
        var chunk: [CatalogRepository.CourseImportInput] = []
        chunk.reserveCapacity(chunkSize)

        for catalogCourse in dedupedCourses {
            let courseKey = CatalogImportTransforms.normalizeCourseCode(catalogCourse.courseCode)
            let extracted = CatalogImportTransforms.extractCreditsFromTitleAndClean(catalogCourse.title)
            let incomingTitle = CatalogImportTransforms.normalize(extracted.cleanTitle)
            let incomingDescriptionRaw = CatalogImportTransforms.normalize(catalogCourse.description)
            let incomingDescription = CatalogImportTransforms.sanitizeCatalogDescription(
                incomingDescriptionRaw,
                courseCode: catalogCourse.courseCode,
                title: catalogCourse.title
            )
            let incomingDepartment = CatalogImportTransforms.normalize(catalogCourse.department)
            let incomingCredits = catalogCourse.credits
            let finalTitle: String = {
                if !incomingTitle.isEmpty, incomingTitle.caseInsensitiveCompare(courseKey) != .orderedSame {
                    return incomingTitle
                }
                return courseKey
            }()
            let descriptionIsInvalid = CatalogImportTransforms.isInvalidCatalogDescription(incomingDescription)
            let finalDescription = descriptionIsInvalid ? nil : incomingDescription
            let finalDepartment = incomingDepartment.isEmpty ? nil : incomingDepartment
            let finalCredits = Int16(max(0, incomingCredits))

            var departmentID: UUID?
            if let finalDepartment {
                let key = finalDepartment.lowercased()
                departmentID = departmentLookup[key]?.id
            }

            chunk.append(
                CatalogRepository.CourseImportInput(
                    courseCode: courseKey,
                    title: finalTitle,
                    credits: finalCredits > 0 ? finalCredits : 3,
                    descriptionText: finalDescription,
                    department: finalDepartment,
                    departmentID: departmentID,
                    isArchived: false
                )
            )

            if chunk.count >= chunkSize {
                try repo.upsertImportedCourses(universityID: university.id, inputs: chunk)
                chunk.removeAll(keepingCapacity: true)
            }
        }

        if !chunk.isEmpty {
            try repo.upsertImportedCourses(universityID: university.id, inputs: chunk)
        }

        let requirementInputs = schoolProfile.degreeRequirements.enumerated().map { index, degreeReq in
            let requiredCSV = degreeReq.requiredCourses?.joined(separator: ", ")
            let requiredDetailedJSON = degreeReq.requiredCoursesDetailed.flatMap {
                AcademicProgramHelpers.encodeDetailedCourseList($0)
            }
            let selectJSON = degreeReq.selectFrom.flatMap { AcademicProgramHelpers.encodeJSONCourseList($0) }
            let selectDetailedJSON = degreeReq.selectFromDetailed.flatMap {
                AcademicProgramHelpers.encodeDetailedCourseList($0)
            }
            return CatalogRepository.DegreeRequirementImportInput(
                id: degreeReq.id,
                major: degreeReq.major,
                category: degreeReq.category,
                degreeType: degreeReq.degreeType,
                programURL: nil,
                sectionOrder: Int16(index),
                creditsRequired: Int16(max(0, degreeReq.creditsRequired)),
                descriptionText: degreeReq.description,
                requiredCourses: requiredCSV,
                requiredCoursesDetailedJSON: requiredDetailedJSON,
                selectFromJSON: selectJSON,
                selectFromDetailedJSON: selectDetailedJSON,
                selectCount: Int16(max(0, degreeReq.selectCount ?? 0)),
                requirementKind: degreeReq.requirementKind?.rawValue,
                parentCategory: degreeReq.parentCategory,
                displayTitle: degreeReq.displayTitle,
                trackVariant: nil,
                requirementsHash: nil
            )
        }
        try repo.upsertDegreeRequirements(universityID: university.id, inputs: requirementInputs)

        if policy.archiveMissingCourses {
            try repo.archiveCoursesNotInCodes(universityID: university.id, scrapedCodes: scrapedCodes)
        }

        try repo.activateUniversity(id: university.id, name: schoolProfile.schoolName)
        CatalogStoreCoordinator.shared.upsertRegistryRecord(
            schoolID: schoolID,
            universityID: university.id,
            universityName: schoolProfile.schoolName
        )
        try appDataStore.catalogSave()
        ModelMergeCoalescer.flushNow()

        if let profile = try appDataStore.profileRepository.fetchPrimaryProfile() {
            profile.collegeName = schoolProfile.schoolName
            try appDataStore.profileSave()
        }

        AppDataStoreBridge.syncActiveCatalogSchool(universityName: schoolProfile.schoolName)
        appDataStore.bumpCatalogDataRevision()

        CatalogIngestPipeline.postCatalogDataDidCommit(
            universityID: university.id,
            reason: "local store catalog import committed"
        )
    }

    private static func stableUniversityID(for profile: SchoolProfile) -> UUID {
        if let uuid = UUID(uuidString: profile.schoolID.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return uuid
        }
        let schoolID = CatalogStoreCoordinator.shared.schoolID(for: profile.schoolName)
        if let match = CatalogStoreCoordinator.shared.loadRegistry().first(where: {
            $0.schoolID == schoolID
                || $0.universityName.caseInsensitiveCompare(profile.schoolName) == .orderedSame
        }) {
            return match.universityID
        }
        return UUID()
    }

    private static func storeSchoolPolicyMetadata(
        _ metadata: SchoolPolicyMetadata,
        universityID: UUID?,
        universityName: String
    ) {
        guard let encoded = try? JSONEncoder().encode(metadata) else { return }
        let defaultsKey = "catalog.schoolPolicyMetadata"
        var dataByKey = UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: Data] ?? [:]
        let keys = [
            metadata.schoolID,
            metadata.schoolName,
            universityID?.uuidString,
            universityName
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        for key in Set(keys) where !key.isEmpty {
            dataByKey[key] = encoded
        }
        UserDefaults.standard.set(dataByKey, forKey: defaultsKey)
    }
}
