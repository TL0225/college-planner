// CatalogSchoolImportService.swift
// Feature: Catalog
// Purpose: Catalog module — ImportPolicy.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import os
import SwiftData

/// local store-only school catalog import (Phase 7f — no local store).
@MainActor
enum CatalogSchoolImportService {
    struct ImportPolicy: Sendable {
        let archiveMissingCourses: Bool

        static let fullSnapshot = ImportPolicy(archiveMissingCourses: true)
        static let preserveExistingCourses = ImportPolicy(archiveMissingCourses: false)
    }

    private struct StreamingImportSession: Sendable {
        let universityID: UUID
        let departmentIDByKey: [String: UUID]
    }

    @MainActor private static var streamingSessions: [String: StreamingImportSession] = [:]

    static func importSchoolCatalog(
        _ schoolProfile: SchoolProfile,
        policy: ImportPolicy = .fullSnapshot,
        appDataStore: AppDataStore = .shared
    ) async throws {
        try await BackgroundServiceOnDemand.runThrowing(id: "catalog_school_import") {
            try await LoadOperationTrace.withSpan(
                name: "ImportSchoolCatalog",
                category: .catalog,
                executionContext: .background,
                metadata: [
                    "school": schoolProfile.schoolName,
                    "courses": "\(schoolProfile.courses.count)"
                ]
            ) {
                try await importSchoolCatalogImpl(schoolProfile, policy: policy, appDataStore: appDataStore)
            }
        }
    }

    /// Upserts one scraped course chunk during ModernCampus streaming without revision bumps.
    static func upsertCourseChunk(
        courses: [CatalogCourse],
        schoolID: String,
        schoolName: String,
        catalogURL: String,
        appDataStore: AppDataStore = .shared
    ) async throws {
        guard !courses.isEmpty else { return }
        let session = try streamingSession(
            schoolID: schoolID,
            schoolName: schoolName,
            catalogURL: catalogURL,
            appDataStore: appDataStore
        )
        let inputs = await Task.detached(priority: .utility) {
            CatalogImportTransforms.buildCourseImportInputs(
                from: courses,
                departmentIDByKey: session.departmentIDByKey
            )
        }.value
        guard !inputs.isEmpty else { return }

        try await LoadOperationTrace.withSpan(
            name: "CatalogUpsertChunk",
            category: .catalog,
            executionContext: .background,
            metadata: [
                "school": schoolID,
                "courses": "\(inputs.count)"
            ]
        ) {
            try await persistCourseInputs(
                universityID: session.universityID,
                inputs: inputs,
                appDataStore: appDataStore
            )
        }
    }

    static func clearStreamingImportSession(schoolID: String) {
        streamingSessions.removeValue(forKey: schoolID)
    }

    private static func importSchoolCatalogImpl(
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
        let departmentIDByKey = try repo.departmentLookup(universityID: university.id).mapValues(\.id)

        let dedupedCourses = CatalogImportTransforms.deduplicatedCourses(schoolProfile.courses)
        let scrapedCodes = Set(dedupedCourses.map { CatalogImportTransforms.normalizeCourseCode($0.courseCode) })
        let courseInputs = await Task.detached(priority: .utility) {
            CatalogImportTransforms.buildCourseImportInputs(
                from: dedupedCourses,
                departmentIDByKey: departmentIDByKey
            )
        }.value
        let requirementInputs = buildRequirementInputs(from: schoolProfile.degreeRequirements)

        let prepared = CatalogSchoolImportWriter.PreparedImport(
            universityID: university.id,
            universityName: schoolProfile.schoolName,
            courseChunks: CatalogSchoolImportWriter.chunk(courseInputs),
            requirementInputs: requirementInputs,
            scrapedCodes: scrapedCodes,
            archiveMissingCourses: policy.archiveMissingCourses
        )

        try await persistPreparedImport(prepared, appDataStore: appDataStore)

        CatalogStoreCoordinator.shared.upsertRegistryRecord(
            schoolID: schoolID,
            universityID: university.id,
            universityName: schoolProfile.schoolName
        )
        ModelMergeCoalescer.flushNow()

        if let profile = try appDataStore.profileRepository.fetchPrimaryProfile() {
            profile.collegeName = schoolProfile.schoolName
            try appDataStore.profileSave()
        }

        AppDataStoreBridge.syncActiveCatalogSchool(universityName: schoolProfile.schoolName)
        appDataStore.bumpCatalogDataRevision()

        CatalogIngestPipeline.postCatalogDataDidCommit(
            universityID: university.id,
            reason: "local store catalog import committed",
            commitPhase: .profile,
            programCount: requirementInputs.count,
            schoolID: schoolID
        )
    }

    private static func streamingSession(
        schoolID: String,
        schoolName: String,
        catalogURL: String,
        appDataStore: AppDataStore
    ) throws -> StreamingImportSession {
        if let cached = streamingSessions[schoolID] {
            return cached
        }

        try appDataStore.setActiveCatalogSchoolID(schoolID)
        guard let repo = appDataStore.catalogRepository else {
            throw NSError(
                domain: "CatalogImport",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Catalog local store container is not available."]
            )
        }

        let profile = SchoolProfile(
            schoolID: schoolID,
            schoolName: schoolName,
            catalogURL: catalogURL,
            version: "streaming",
            lastUpdated: Date(),
            courses: [],
            degreeRequirements: [],
            policies: SchoolPolicies(
                transferCreditLimit: nil,
                minorTransferLimit: nil,
                maxCreditsPerSemester: nil,
                minCreditsForFullTime: nil,
                gradeForCredit: nil,
                repeatCoursePolicy: nil
            )
        )
        let universityID = stableUniversityID(for: profile)
        let university = try repo.ensureUniversityForImport(
            id: universityID,
            name: schoolName,
            catalogURL: catalogURL
        )
        let departmentIDByKey = try repo.departmentLookup(universityID: university.id).mapValues(\.id)
        let session = StreamingImportSession(
            universityID: university.id,
            departmentIDByKey: departmentIDByKey
        )
        streamingSessions[schoolID] = session
        return session
    }

    private static func buildRequirementInputs(
        from degreeRequirements: [DegreeRequirement]
    ) -> [CatalogRepository.DegreeRequirementImportInput] {
        CatalogRequirementAST.attachAST(to: degreeRequirements).enumerated().map { index, degreeReq in
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
                requirementsHash: nil,
                catalogStableID: nil,
                provenanceJSON: nil,
                extractionConfidence: nil,
                signalSource: nil,
                parserVersion: CatalogParserCapability.version,
                programAttachmentConfidence: nil,
                requirementPredicateJSON: CatalogRequirementAST.encode(degreeReq.requirementPredicate),
                catalogEditionID: nil
            )
        }
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

    private static func persistPreparedImport(
        _ prepared: CatalogSchoolImportWriter.PreparedImport,
        appDataStore: AppDataStore
    ) async throws {
        if CollegeTestRuntime.isUnitTestProcess {
            try CatalogSchoolImportWriter.persistPreparedImport(
                prepared,
                context: appDataStore.profileContext
            )
            ModelMergeCoalescer.scheduleSave(appDataStore.profileContext)
            return
        }
        let container = appDataStore.profileContainer
        try await BackgroundServiceExecutor.persistOffMain(container: container) { context in
            try CatalogSchoolImportWriter.persistPreparedImport(prepared, context: context)
        }
    }

    private static func persistCourseInputs(
        universityID: UUID,
        inputs: [CatalogRepository.CourseImportInput],
        appDataStore: AppDataStore
    ) async throws {
        if CollegeTestRuntime.isUnitTestProcess {
            try CatalogSchoolImportWriter.upsertCourses(
                universityID: universityID,
                inputs: inputs,
                context: appDataStore.profileContext
            )
            ModelMergeCoalescer.scheduleSave(appDataStore.profileContext)
            return
        }
        let container = appDataStore.profileContainer
        try await BackgroundServiceExecutor.persistOffMain(container: container) { context in
            try CatalogSchoolImportWriter.upsertCourses(
                universityID: universityID,
                inputs: inputs,
                context: context
            )
            if context.hasChanges {
                try context.save()
            }
        }
    }
}
