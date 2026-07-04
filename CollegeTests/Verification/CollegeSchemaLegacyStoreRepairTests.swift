// CollegeSchemaLegacyStoreRepairTests.swift
// Snow Leopard V&V: legacy store repair path documented and smoke-tested (DM-M4, SM2).

import SwiftData
import XCTest
@testable import College

@MainActor
final class CollegeSchemaLegacyStoreRepairTests: XCTestCase {
    func testOpenContainerCreatesFreshStoreWhenMissing() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("College-repair-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        let container = try CollegeSchemaLegacyStoreRepair.openContainer(
            schema: CollegeModelContainerFactory.unifiedSchema,
            migrationPlan: CollegeSchemaMigrationPlan.self,
            url: url,
            partition: .unified
        )
        XCTAssertNotNil(container.mainContext)
    }

    func testRepairStoreReturnsFalseForMissingFile() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-\(UUID().uuidString).sqlite")
        let repaired = CollegeSchemaLegacyStoreRepair.repairStore(
            at: url,
            partition: .unified,
            targetSchema: CollegeModelContainerFactory.unifiedSchema,
            configuration: ModelConfiguration(url: url)
        )
        XCTAssertFalse(repaired)
    }
}
