// SchemaMigrationPlanTests.swift
// Feature: Shared
// Purpose: Shared module — SchemaMigrationPlanTests.
// Data: CollegePersistence / repositories when applicable.

import SwiftData
import XCTest
@testable import College

/// Phase 7g: versioned schema identifier + in-memory container smoke.
@MainActor
final class SchemaMigrationPlanTests: XCTestCase {
    func testCollegeSchemaV1_0_versionIdentifier() {
        XCTAssertEqual(CollegeSchemaV1_0.versionIdentifier, Schema.Version(1, 0, 0))
    }

    func testCollegeSchemaV1_versionIdentifier() {
        XCTAssertEqual(CollegeSchemaV1.versionIdentifier, Schema.Version(1, 1, 0))
    }

    func testCollegeSchemaV1_2_versionIdentifier() {
        XCTAssertEqual(CollegeSchemaV1_2.versionIdentifier, Schema.Version(1, 2, 0))
    }

    func testCollegeSchemaV1_3_versionIdentifier() {
        XCTAssertEqual(CollegeSchemaV1_3.versionIdentifier, Schema.Version(1, 3, 0))
    }

    func testCollegeSchemaV1_4_versionIdentifier() {
        XCTAssertEqual(CollegeSchemaV1_4.versionIdentifier, Schema.Version(1, 4, 0))
    }

    func testCollegeSchemaV1_5_versionIdentifier() {
        XCTAssertEqual(CollegeSchemaV1_5.versionIdentifier, Schema.Version(1, 5, 0))
    }

    func testCollegeSchemaV1_6_versionIdentifier() {
        XCTAssertEqual(CollegeSchemaV1_6.versionIdentifier, Schema.Version(1, 6, 0))
    }

    func testCollegeSchemaV1_7_versionIdentifier() {
        XCTAssertEqual(CollegeSchemaV1_7.versionIdentifier, Schema.Version(1, 7, 0))
    }

    func testCollegeSchemaV1_8_versionIdentifier() {
        XCTAssertEqual(CollegeSchemaV1_8.versionIdentifier, Schema.Version(1, 8, 0))
    }

    func testCollegeSchemaV1_9_versionIdentifier() {
        XCTAssertEqual(CollegeSchemaV1_9.versionIdentifier, Schema.Version(1, 9, 0))
    }

    func testCollegeSchemaMigrationPlan_stages() {
        XCTAssertEqual(CollegeSchemaMigrationPlan.schemas.count, 7)
        XCTAssertEqual(CollegeSchemaMigrationPlan.stages.count, 6)
        XCTAssertFalse(CollegeSchemaMigrationPlan.schemas.contains(where: { $0 == CollegeSchemaV1_2.self }))
        XCTAssertFalse(CollegeSchemaMigrationPlan.schemas.contains(where: { $0 == CollegeSchemaV1_5.self }))
        XCTAssertFalse(CollegeSchemaMigrationPlan.schemas.contains(where: { $0 == CollegeSchemaV1_7.self }))
        XCTAssertTrue(CollegeSchemaMigrationPlan.schemas.contains(where: { $0 == CollegeSchemaV1_6.self }))
        XCTAssertTrue(CollegeSchemaMigrationPlan.schemas.contains(where: { $0 == CollegeSchemaV1_8.self }))
        XCTAssertTrue(CollegeSchemaMigrationPlan.schemas.contains(where: { $0 == CollegeSchemaV1_9.self }))
    }

    func testOnDiskProfile_upgradesFromV1_0ToV1_9() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("College-v10-upgrade-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        let seedSchema = Schema(CollegeSchemaV1_0.models, version: CollegeSchemaV1_0.versionIdentifier)
        let configuration = ModelConfiguration(url: url)
        let seedContainer = try ModelContainer(for: seedSchema, configurations: configuration)
        seedContainer.mainContext.insert(Profile(name: "V1_0 Upgrade"))
        try seedContainer.mainContext.save()

        let migrated = try CollegeSchemaLegacyStoreRepair.openContainer(
            schema: CollegeModelContainerFactory.profileSchema,
            migrationPlan: CollegeSchemaMigrationPlan.self,
            url: url,
            partition: .unified
        )
        let names = try migrated.mainContext.fetch(FetchDescriptor<Profile>()).compactMap(\.name)
        XCTAssertEqual(names, ["V1_0 Upgrade"])
        XCTAssertEqual(
            CollegeModelContainerFactory.profileSchema.version,
            CollegeSchemaV1_9.versionIdentifier
        )
    }

    func testOnDiskProfile_upgradesFromV1_4ToV1_9() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("College-v14-upgrade-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        let seedSchema = Schema(CollegeSchemaV1_4.models, version: CollegeSchemaV1_4.versionIdentifier)
        let configuration = ModelConfiguration(url: url)
        let seedContainer = try ModelContainer(for: seedSchema, configurations: configuration)
        seedContainer.mainContext.insert(Profile(name: "V1_4 Upgrade"))
        try seedContainer.mainContext.save()

        let migrated = try CollegeSchemaLegacyStoreRepair.openContainer(
            schema: CollegeModelContainerFactory.profileSchema,
            migrationPlan: CollegeSchemaMigrationPlan.self,
            url: url,
            partition: .unified
        )
        let names = try migrated.mainContext.fetch(FetchDescriptor<Profile>()).compactMap(\.name)
        XCTAssertEqual(names, ["V1_4 Upgrade"])
        XCTAssertEqual(
            CollegeModelContainerFactory.profileSchema.version,
            CollegeSchemaV1_9.versionIdentifier
        )
    }

    func testMigrationPlan_originIsV1_0AndHeadIsV1_9() {
        XCTAssertTrue(CollegeSchemaMigrationPlan.schemas.first == CollegeSchemaV1_0.self)
        XCTAssertTrue(CollegeSchemaMigrationPlan.schemas.last == CollegeSchemaV1_9.self)
    }

    func testCollegeSchemaMigrationPlan_canOpenProfileContainerWithoutDuplicateChecksumCrash() throws {
        _ = try CollegeModelContainerFactory.makeProfileContainer(inMemory: true)
    }

    func testCollegeSchemaMigrationPlan_canOpenOnDiskProfileContainerWithoutDuplicateChecksumCrash() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("College-schema-smoke-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        let configuration = ModelConfiguration(url: url)
        _ = try ModelContainer(
            for: CollegeModelContainerFactory.profileSchema,
            migrationPlan: CollegeSchemaMigrationPlan.self,
            configurations: configuration
        )
        _ = try ModelContainer(
            for: CollegeModelContainerFactory.profileSchema,
            migrationPlan: CollegeSchemaMigrationPlan.self,
            configurations: configuration
        )
    }

    func testCollegeSchemaMigrationPlan_canOpenOnDiskCatalogContainerWithoutDuplicateChecksumCrash() throws {
        let schoolID = "schema-smoke-\(UUID().uuidString.prefix(8))"
        let url = CollegeModelContainerFactory.catalogStoreURL(for: schoolID)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let configuration = ModelConfiguration(url: url)
        _ = try ModelContainer(
            for: CollegeModelContainerFactory.catalogSchema,
            migrationPlan: CollegeSchemaMigrationPlan.self,
            configurations: configuration
        )
    }

    func testCollegeSchemaV1_4_modelsIncludeTransferEntities() {
        let modelNames = CollegeSchemaV1_4.models.map { String(describing: $0) }
        XCTAssertTrue(modelNames.contains(where: { $0.contains("TransferEquivalency") }))
        XCTAssertTrue(modelNames.contains(where: { $0.contains("TransferProofRecord") }))
    }

    func testCollegeSchemaV1_6_modelsIncludeCatalogHierarchy() {
        let modelNames = CollegeSchemaV1_6.models.map { String(describing: $0) }
        XCTAssertTrue(modelNames.contains(where: { $0.contains("CatalogCollege") }))
        XCTAssertTrue(modelNames.contains(where: { $0.contains("CatalogEdition") }))
    }

    func testCollegeSchemaV1_8_modelsIncludeApplyPreferences() {
        CollegeSchemaV1_8.assertDistinctFromV1_6()
        let modelNames = CollegeSchemaV1_8.models.map { String(describing: $0) }
        XCTAssertTrue(modelNames.contains(where: { $0.contains("CareerApplicationPreferences") }))
        XCTAssertGreaterThan(CollegeSchemaV1_8.models.count, CollegeSchemaV1_6.models.count)
    }

    func testCollegeSchemaV1_8_isNotChecksumOnlyStampOfV1_6() throws {
        let v6IDs = Set(CollegeSchemaV1_6.models.map { ObjectIdentifier($0) })
        let v8IDs = Set(CollegeSchemaV1_8.models.map { ObjectIdentifier($0) })
        XCTAssertTrue(v8IDs.isStrictSuperset(of: v6IDs))
        _ = try CollegeModelContainerFactory.makeProfileContainer(inMemory: true)
    }

    func testCollegeSchemaV1_9_assertDistinctFromV1_8() {
        CollegeSchemaV1_9.assertDistinctFromV1_8()
        XCTAssertEqual(CollegeSchemaV1_9.models.count, CollegeSchemaV1_8.models.count)
    }

    func testUnifiedModelTypes_matchCollegeSchemaV1_9() {
        let factoryIDs = Set(CollegeModelContainerFactory.unifiedModelTypes.map { ObjectIdentifier($0) })
        let v19IDs = Set(CollegeSchemaV1_9.models.map { ObjectIdentifier($0) })
        XCTAssertEqual(factoryIDs, v19IDs)
    }

    func testFactorySchemas_useCollegeSchemaV1_9Version() {
        XCTAssertEqual(CollegeModelContainerFactory.unifiedSchema.version, CollegeSchemaV1_9.versionIdentifier)
        XCTAssertEqual(CollegeModelContainerFactory.profileSchema.version, CollegeSchemaV1_9.versionIdentifier)
        XCTAssertEqual(CollegeModelContainerFactory.catalogSchema.version, CollegeSchemaV1_9.versionIdentifier)
    }

    func testProfileContainer_newProfileFieldsRoundTrip() throws {
        let container = try CollegeModelContainerFactory.makeProfileContainer(inMemory: true)
        let context = container.mainContext
        let profile = Profile(name: "Skills smoke")
        profile.skillsJSON = #"["Swift","Python"]"#
        profile.linksJSON = #"["https://github.com/example"]"#
        context.insert(profile)

        let experience = Experience(isCurrent: true)
        experience.title = "Intern"
        experience.company = "Acme"
        experience.technologies = "Swift, SQL"
        experience.profile = profile
        context.insert(experience)

        try context.save()

        let fetchedProfile = try context.fetch(FetchDescriptor<Profile>()).first
        XCTAssertEqual(fetchedProfile?.skillsJSON, #"["Swift","Python"]"#)
        XCTAssertEqual(fetchedProfile?.linksJSON, #"["https://github.com/example"]"#)

        let fetchedExperience = try context.fetch(FetchDescriptor<Experience>()).first
        XCTAssertEqual(fetchedExperience?.technologies, "Swift, SQL")
    }

    func testProfileContainer_inMemory_insertsAndFetches() throws {
        let container = try CollegeModelContainerFactory.makeProfileContainer(inMemory: true)
        let context = container.mainContext
        let profile = Profile(name: "Schema V1 Smoke")
        context.insert(profile)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Profile>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.name, "Schema V1 Smoke")
    }

    func testCatalogContainer_inMemory_insertsAndFetches() throws {
        let container = try CollegeModelContainerFactory.makeCatalogContainer(
            schoolID: "schema-v1-\(UUID().uuidString.prefix(8))",
            inMemory: true
        )
        let context = container.mainContext
        let uni = University(name: "Schema V1 U", isActive: true)
        context.insert(uni)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<University>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.name, "Schema V1 U")
    }

    func testUnifiedInMemoryContainer_spansProfileAndCatalogModels() throws {
        let container = try CollegeModelContainerFactory.makeUnifiedInMemoryContainer()
        let context = container.mainContext

        context.insert(Profile(name: "Unified"))
        context.insert(University(name: "Unified U", isActive: true))
        try context.save()

        XCTAssertEqual(try context.fetch(FetchDescriptor<Profile>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<University>()).count, 1)
    }

    func testLegacyStoreRepair_recoversOrphanV1_2Stamp() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("College-orphan-v12-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        // Stores stamped 1.2.0 were schema-identical to 1.1.0; use the V1 models but stamp 1.2.0.
        let orphanSchema = Schema(CollegeSchemaV1.models, version: CollegeSchemaV1_2.versionIdentifier)
        let orphanConfig = ModelConfiguration(url: url)
        let orphanContainer = try ModelContainer(for: orphanSchema, configurations: orphanConfig)
        orphanContainer.mainContext.insert(Profile(name: "Orphan V1_2"))
        try orphanContainer.mainContext.save()

        XCTAssertTrue(
            CollegeSchemaLegacyStoreRepair.restampOrphanStore(
                at: url,
                partition: .profile,
                configuration: orphanConfig
            )
        )
    }

    func testLegacyStoreRepair_recoversOrphanV1_5Stamp() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("College-orphan-v15-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        let orphanSchema = Schema(CollegeSchemaV1_4.models, version: CollegeSchemaV1_5.versionIdentifier)
        let orphanConfig = ModelConfiguration(url: url)
        let orphanContainer = try ModelContainer(for: orphanSchema, configurations: orphanConfig)
        orphanContainer.mainContext.insert(Profile(name: "Orphan V1_5"))
        try orphanContainer.mainContext.save()

        XCTAssertTrue(
            CollegeSchemaLegacyStoreRepair.restampOrphanStore(
                at: url,
                partition: .profile,
                configuration: orphanConfig
            )
        )
    }

    func testLegacyStoreRepair_recoversOrphanV1_4Stamp() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("College-orphan-v14-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        let orphanSchema = Schema(CollegeSchemaV1_4.models, version: Schema.Version(1, 4, 0))
        let orphanConfig = ModelConfiguration(url: url)
        let orphanContainer = try ModelContainer(for: orphanSchema, configurations: orphanConfig)
        orphanContainer.mainContext.insert(Profile(name: "Orphan V1_4"))
        try orphanContainer.mainContext.save()

        let reopened = try CollegeSchemaLegacyStoreRepair.openContainer(
            schema: CollegeModelContainerFactory.profileSchema,
            migrationPlan: CollegeSchemaMigrationPlan.self,
            url: url,
            partition: .unified
        )
        let profiles = try reopened.mainContext.fetch(FetchDescriptor<Profile>())
        XCTAssertEqual(profiles.first?.name, "Orphan V1_4")
    }

    func testLegacyStoreRepair_opensLiveProfileStoreWhenPresent() throws {
        let url = CollegeModelContainerFactory.profileStoreURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        let container = try CollegeSchemaLegacyStoreRepair.openContainer(
            schema: CollegeModelContainerFactory.profileSchema,
            migrationPlan: CollegeSchemaMigrationPlan.self,
            url: url,
            partition: .unified
        )
        _ = try container.mainContext.fetch(FetchDescriptor<Profile>())
    }

    func testLiveStoreOpensWithoutMigrationPlanWhenStagedMetadataIsCorrupt() throws {
        let url = CollegeModelContainerFactory.profileStoreURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        let configuration = ModelConfiguration(url: url)
        let container = try ModelContainer(
            for: CollegeModelContainerFactory.unifiedSchema,
            configurations: configuration
        )
        _ = try container.mainContext.fetch(FetchDescriptor<Profile>())
    }

    func testProfileContainer_focusBlockRoundTrip() throws {
        let container = try CollegeModelContainerFactory.makeProfileContainer(inMemory: true)
        let repo = ProfileRepository(context: container.mainContext)
        let block = FocusBlock(
            id: UUID(),
            title: "Deep work",
            startHour: 9,
            endHour: 12,
            weekdays: [2, 3, 4]
        )
        try repo.replaceFocusBlocks([block])

        let fetched = try repo.fetchFocusBlocks()
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.toFocusBlock()?.title, "Deep work")
        XCTAssertEqual(fetched.first?.toFocusBlock()?.weekdays, [2, 3, 4])
    }
}

// MARK: - AppDataStore revision sync + launch recovery

extension SchemaMigrationPlanTests {
    func testAppDataStore_profileSave_syncsCollegePersistenceRevision() throws {
        let store = AppDataStore.shared
        let persistence = CollegePersistence.shared
        let beforePersistence = persistence.profileRevision
        let beforeStore = store.profileRevision

        store.profileContext.insert(Profile(name: "Revision sync smoke"))
        XCTAssertTrue(try store.profileSave())

        XCTAssertEqual(persistence.profileRevision, beforePersistence + 1)
        XCTAssertEqual(store.profileRevision, beforeStore + 1)
        XCTAssertEqual(store.profileRevision, persistence.profileRevision)
    }

    func testCollegePersistence_bumpProfileRevision_syncsAppDataStoreCounter() {
        let store = AppDataStore.shared
        let persistence = CollegePersistence.shared
        let beforePersistence = persistence.profileRevision
        let beforeStore = store.profileRevision

        persistence.bumpProfileRevision()

        XCTAssertEqual(persistence.profileRevision, beforePersistence + 1)
        XCTAssertEqual(store.profileRevision, beforeStore + 1)
    }

    func testAppDataStore_catalogSave_syncsCollegePersistenceRevision() throws {
        let store = AppDataStore.shared
        let persistence = CollegePersistence.shared
        try store.useInMemoryCatalogForUnitTesting(schoolID: "revision-sync-\(UUID().uuidString.prefix(8))")
        let beforePersistence = persistence.catalogDataRevision
        let beforeStore = store.catalogDataRevision

        let context = try XCTUnwrap(store.activeCatalogContext)
        context.insert(University(name: "Revision Sync U", isActive: true))
        XCTAssertTrue(try store.catalogSave())

        XCTAssertEqual(persistence.catalogDataRevision, beforePersistence + 1)
        XCTAssertEqual(store.catalogDataRevision, beforeStore + 1)
        XCTAssertEqual(store.catalogDataRevision, persistence.catalogDataRevision)
    }

    func testAppDataStore_recoversOrphanProfileStoreAfterRepair() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("College-appdatastore-recovery-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        let orphanSchema = Schema(
            CollegeModelContainerFactory.profileModelTypes,
            version: CollegeSchemaV1_2.versionIdentifier
        )
        let orphanConfig = ModelConfiguration(url: url)
        let orphanContainer = try ModelContainer(for: orphanSchema, configurations: orphanConfig)
        orphanContainer.mainContext.insert(Profile(name: "AppDataStore recovery"))
        try orphanContainer.mainContext.save()

        XCTAssertTrue(
            CollegeSchemaLegacyStoreRepair.repairStore(
                at: url,
                partition: .profile,
                targetSchema: CollegeModelContainerFactory.profileSchema,
                configuration: orphanConfig
            )
        )

        let reopened = try CollegeSchemaLegacyStoreRepair.openContainer(
            schema: CollegeModelContainerFactory.profileSchema,
            migrationPlan: CollegeSchemaMigrationPlan.self,
            url: url,
            partition: .profile
        )
        let profiles = try reopened.mainContext.fetch(FetchDescriptor<Profile>())
        XCTAssertEqual(profiles.first?.name, "AppDataStore recovery")
    }
}
