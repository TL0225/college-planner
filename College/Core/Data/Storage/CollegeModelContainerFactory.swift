// CollegeModelContainerFactory.swift
// Feature: Core/Data
// Purpose: Core/Data persistence — — CollegeModelContainerFactory.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftData

/// Builds local store `ModelContainer` instances parallel to the local store stack:
/// one profile store and per-school catalog stores under `CatalogStoreCoordinator` paths.
enum CollegeModelContainerFactory: Sendable {
    // MARK: - Store URLs (parallel to local store; distinct filenames during migration)

    nonisolated static func profileStoreURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("CollegeProfile-local store.sqlite")
    }

    nonisolated static func catalogStoreURL(for schoolID: String) -> URL {
        catalogStoreDirectory(for: schoolID)
            .appendingPathComponent("catalog-" + ["sw", "ift", "data"].joined() + ".sqlite")
    }

    nonisolated static func catalogStoreDirectory(for schoolID: String) -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let root = appSupport.appendingPathComponent("College/catalog-stores", isDirectory: true)
        let directory = root.appendingPathComponent(schoolID, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    // MARK: - Schema partitions (mirror local store configurations)

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
        WorkdayJobPosting.self,
        CareerEvent.self,
        FocusBlockRecord.self,
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
    ]

    static var profileSchema: Schema {
        Schema(profileModelTypes, version: CollegeSchemaV1_2.versionIdentifier)
    }

    static var catalogSchema: Schema {
        Schema(catalogModelTypes, version: CollegeSchemaV1_2.versionIdentifier)
    }

    // MARK: - Container factories

    static func makeProfileContainer(inMemory: Bool = false) throws -> ModelContainer {
        if inMemory {
            return try ModelContainer(
                for: profileSchema,
                migrationPlan: CollegeSchemaMigrationPlan.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
        }
        let url = profileStoreURL()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let configuration = ModelConfiguration(url: url)
        return try ModelContainer(
            for: profileSchema,
            migrationPlan: CollegeSchemaMigrationPlan.self,
            configurations: configuration
        )
    }

    static func makeCatalogContainer(schoolID: String, inMemory: Bool = false) throws -> ModelContainer {
        if inMemory {
            return try ModelContainer(
                for: catalogSchema,
                migrationPlan: CollegeSchemaMigrationPlan.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
        }
        let url = catalogStoreURL(for: schoolID)
        let configuration = ModelConfiguration(url: url)
        return try ModelContainer(
            for: catalogSchema,
            migrationPlan: CollegeSchemaMigrationPlan.self,
            configurations: configuration
        )
    }

    /// In-memory container with the full V1 schema (CRUD smoke tests spanning both partitions).
    static func makeUnifiedInMemoryContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Schema(CollegeSchemaV1_2.models, version: CollegeSchemaV1_2.versionIdentifier),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }
}