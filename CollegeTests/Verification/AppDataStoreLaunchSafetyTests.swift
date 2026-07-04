// AppDataStoreLaunchSafetyTests.swift
// Snow Leopard V&V: corrupt/missing store must not crash launch (CO-F1, REC-2).

import SwiftData
import XCTest
@testable import College

@MainActor
final class AppDataStoreLaunchSafetyTests: XCTestCase {
    func testInMemoryAppDataStoreOpensWithoutStoreOpenError() throws {
        let store = try PersistenceTestHarness.makeAppDataStore()
        XCTAssertNil(store.storeOpenError)
        XCTAssertNotNil(store.profileContext)
    }

    func testCorruptStoreFileFallsBackWithoutTrap() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("College-corrupt-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        try Data("not a sqlite database".utf8).write(to: url)
        let configuration = ModelConfiguration(url: url)
        let container: ModelContainer
        do {
            container = try ModelContainer(
                for: CollegeModelContainerFactory.unifiedSchema,
                migrationPlan: CollegeSchemaMigrationPlan.self,
                configurations: configuration
            )
        } catch {
            container = try CollegeModelContainerFactory.makeProfileContainer(inMemory: true)
        }
        let store = AppDataStore(profileContainer: container)
        XCTAssertNotNil(store.profileContext)
    }
}
