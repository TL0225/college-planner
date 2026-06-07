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

    func testCollegeSchemaMigrationPlan_stages() {
        XCTAssertEqual(CollegeSchemaMigrationPlan.schemas.count, 3)
        XCTAssertEqual(CollegeSchemaMigrationPlan.stages.count, 2)
    }

    func testCollegeSchemaV1_modelsMatchFactoryPartitions() {
        let profileIDs = Set(CollegeModelContainerFactory.profileModelTypes.map { ObjectIdentifier($0) })
        let catalogIDs = Set(CollegeModelContainerFactory.catalogModelTypes.map { ObjectIdentifier($0) })
        let v1IDs = Set(CollegeSchemaV1.models.map { ObjectIdentifier($0) })

        XCTAssertEqual(profileIDs.union(catalogIDs), v1IDs)
        XCTAssertTrue(profileIDs.isDisjoint(with: catalogIDs))
    }

    func testFactorySchemas_useCollegeSchemaV1_2Version() {
        XCTAssertEqual(CollegeModelContainerFactory.profileSchema.version, CollegeSchemaV1_2.versionIdentifier)
        XCTAssertEqual(CollegeModelContainerFactory.catalogSchema.version, CollegeSchemaV1_2.versionIdentifier)
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
