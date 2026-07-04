// LaunchSingleCatalogMmapTests.swift
// Feature: Shared
// Purpose: Shared module — LaunchSingleCatalogMmapTests.
// Data: CollegePersistence / repositories when applicable.

import XCTest
@testable import College

@MainActor
final class LaunchSingleCatalogMmapTests: XCTestCase {
    func testSetActiveCatalogSchoolID_usesUnifiedContainer() throws {
        let schoolA = "launch_a_\(UUID().uuidString.prefix(8))"
        let schoolB = "launch_b_\(UUID().uuidString.prefix(8))"
        defer {
            try? AppDataStore.shared.setActiveCatalogSchoolID(nil)
        }

        let store = AppDataStore.shared
        try store.setActiveCatalogSchoolID(nil)

        try store.setActiveCatalogSchoolID(schoolA)
        let firstContainer = try XCTUnwrap(store.activeCatalogContainer)
        XCTAssertEqual(store.activeCatalogSchoolID, schoolA)
        XCTAssertTrue(firstContainer === store.profileContainer)

        try store.setActiveCatalogSchoolID(schoolB)
        XCTAssertEqual(store.activeCatalogSchoolID, schoolB)
        XCTAssertTrue(firstContainer === store.activeCatalogContainer)
        XCTAssertTrue(store.activeCatalogContainer === store.profileContainer)

        try store.setActiveCatalogSchoolID(nil)
        XCTAssertNil(store.activeCatalogContainer)
        XCTAssertNil(store.activeCatalogSchoolID)
    }

    func testLaunchBridge_reusesUnifiedContainer() throws {
        let expectedSchoolID = CatalogStoreCoordinator.shared.schoolID(for: "Launch Bridge U")
        defer {
            try? AppDataStore.shared.setActiveCatalogSchoolID(nil)
        }

        AppDataStoreBridge.syncActiveCatalogSchool(universityName: "Launch Bridge U")

        let store = AppDataStore.shared
        XCTAssertEqual(store.activeCatalogSchoolID, expectedSchoolID)
        let firstContainer = try XCTUnwrap(store.activeCatalogContainer)
        XCTAssertTrue(firstContainer === store.profileContainer)

        AppDataStoreBridge.syncActiveCatalogSchool(universityName: "Launch Bridge U")
        XCTAssertTrue(firstContainer === store.activeCatalogContainer)
    }
}
