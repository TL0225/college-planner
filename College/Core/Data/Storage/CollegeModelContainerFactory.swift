// CollegeModelContainerFactory.swift
// Feature: Core/Data
// Purpose: Core/Data persistence — — CollegeModelContainerFactory.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftData

/// Builds the single on-disk SwiftData store for all app models (profile, planner, career, catalog).
enum CollegeModelContainerFactory: Sendable {
    // MARK: - Store URLs

    /// Canonical single-file store for all SwiftData models.
    nonisolated static func unifiedStoreURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("College.sqlite")
    }

    /// Legacy profile-only filename (pre-unified store).
    nonisolated static func legacyProfileStoreURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("CollegeProfile-local store.sqlite")
    }

    nonisolated static func profileStoreURL() -> URL {
        unifiedStoreURL()
    }

    /// Legacy per-school catalog layout retained for one-time import only.
    nonisolated static func legacyCatalogStoresRootURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let root = appSupport.appendingPathComponent("College/catalog-stores", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    nonisolated static func legacyCatalogStoreURL(for schoolID: String) -> URL {
        legacyCatalogStoreDirectory(for: schoolID)
            .appendingPathComponent("catalog-" + ["sw", "ift", "data"].joined() + ".sqlite")
    }

    nonisolated static func legacyCatalogStoreDirectory(for schoolID: String) -> URL {
        let directory = legacyCatalogStoresRootURL().appendingPathComponent(schoolID, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Backward-compatible alias used by legacy import/export paths.
    nonisolated static func catalogStoresRootURL() -> URL {
        legacyCatalogStoresRootURL()
    }

    nonisolated static func catalogStoreURL(for schoolID: String) -> URL {
        legacyCatalogStoreURL(for: schoolID)
    }

    nonisolated static func catalogStoreDirectory(for schoolID: String) -> URL {
        legacyCatalogStoreDirectory(for: schoolID)
    }

    // MARK: - Schema

    static let profileModelTypes: [any PersistentModel.Type] = [
        PlannerSemester.self,
        PlannerPlan.self,
        PlannerCourse.self,
        CourseGradingCategory.self,
        CalendarEvent.self,
        PlannerTask.self,
        AcademicProfile.self,
        Profile.self,
        Experience.self,
        Achievement.self,
        VaultDocument.self,
        WatchedFolder.self,
        JobApplication.self,
        RecruiterContact.self,
        JobBoardPosting.self,
        CareerEvent.self,
        FocusBlockRecord.self,
        CareerResumeJobMatch.self,
        CareerResumeJobMatchSnapshot.self,
        TransferEquivalency.self,
        TransferProofRecord.self,
        CareerApplicationPreferences.self,
    ]

    static let catalogModelTypes: [any PersistentModel.Type] = [
        University.self,
        CourseCatalog.self,
        CourseOverride.self,
        Department.self,
        Major.self,
        CatalogDegreeRequirement.self,
        RequirementFulfillment.self,
        CatalogPolicyDocument.self,
        CatalogScrapeState.self,
        GraduationPlanTerm.self,
        TransferEquivalency.self,
        TransferProofRecord.self,
        CatalogCollege.self,
        CatalogEdition.self,
    ]

    static var unifiedModelTypes: [any PersistentModel.Type] {
        CollegeSchemaV1_9.models
    }

    static var unifiedSchema: Schema {
        Schema(unifiedModelTypes, version: CollegeSchemaV1_9.versionIdentifier)
    }

    static var profileSchema: Schema {
        unifiedSchema
    }

    static var catalogSchema: Schema {
        Schema(catalogModelTypes, version: CollegeSchemaV1_9.versionIdentifier)
    }

    // MARK: - Container factories

    @MainActor
    static func makeProfileContainer(inMemory: Bool = false) throws -> ModelContainer {
        CollegeSchemaV1_9.assertDistinctFromV1_8()
        if inMemory {
            return try ModelContainer(
                for: unifiedSchema,
                migrationPlan: CollegeSchemaMigrationPlan.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
        }
        let url = try prepareUnifiedStoreOnDisk()
        return try CollegeSchemaLegacyStoreRepair.openContainer(
            schema: unifiedSchema,
            migrationPlan: CollegeSchemaMigrationPlan.self,
            url: url,
            partition: .unified
        )
    }

    @MainActor
    static func makeCatalogContainer(schoolID: String, inMemory: Bool = false) throws -> ModelContainer {
        if inMemory {
            return try makeProfileContainer(inMemory: true)
        }
        return try makeProfileContainer()
    }

    /// In-memory container with the full V1 schema (CRUD smoke tests spanning both partitions).
    @MainActor
    static func makeUnifiedInMemoryContainer() throws -> ModelContainer {
        try makeProfileContainer(inMemory: true)
    }

    // MARK: - On-disk preparation

    @discardableResult
    @MainActor
    static func prepareUnifiedStoreOnDisk() throws -> URL {
        let fm = FileManager.default
        let target = unifiedStoreURL()
        let legacy = legacyProfileStoreURL()

        try fm.createDirectory(
            at: target.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        if !fm.fileExists(atPath: target.path), fm.fileExists(atPath: legacy.path) {
            try fm.moveItem(at: legacy, to: target)
            for suffix in ["-wal", "-shm"] {
                let legacySidecar = URL(fileURLWithPath: legacy.path + suffix)
                guard fm.fileExists(atPath: legacySidecar.path) else { continue }
                try fm.moveItem(at: legacySidecar, to: URL(fileURLWithPath: target.path + suffix))
            }
        }

        return target
    }
}
