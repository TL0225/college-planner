// LaunchSingleCatalogMmapTests.swift
// Feature: Shared
// Purpose: Shared module — LaunchSingleCatalogMmapTests.
// Data: CollegePersistence / repositories when applicable.

import XCTest
@testable import College

@MainActor
final class LaunchSingleCatalogMmapTests: XCTestCase {
    func testSetActiveCatalogSchoolID_keepsOnlyOneContainer() throws {
        let schoolA = "launch_a_\(UUID().uuidString.prefix(8))"
        let schoolB = "launch_b_\(UUID().uuidString.prefix(8))"
        defer {
            try? AppDataStore.shared.setActiveCatalogSchoolID(nil)
            for schoolID in [schoolA, schoolB] {
                ModelStoreMaintenance.removeSQLiteBundle(
                    at: CollegeModelContainerFactory.catalogStoreURL(for: schoolID)
                )
            }
        }

        let store = AppDataStore.shared
        try store.setActiveCatalogSchoolID(nil)

        try store.setActiveCatalogSchoolID(schoolA)
        let firstContainer = try XCTUnwrap(store.activeCatalogContainer)
        XCTAssertEqual(store.activeCatalogSchoolID, schoolA)

        try store.setActiveCatalogSchoolID(schoolB)
        XCTAssertEqual(store.activeCatalogSchoolID, schoolB)
        XCTAssertNotNil(store.activeCatalogContainer)
        XCTAssertFalse(firstContainer === store.activeCatalogContainer)

        try store.setActiveCatalogSchoolID(nil)
        XCTAssertNil(store.activeCatalogContainer)
        XCTAssertNil(store.activeCatalogSchoolID)
    }

    func testLaunchBridge_reusesSingleCatalogContainer() throws {
        let expectedSchoolID = CatalogStoreCoordinator.shared.schoolID(for: "Launch Bridge U")
        defer {
            try? AppDataStore.shared.setActiveCatalogSchoolID(nil)
            ModelStoreMaintenance.removeSQLiteBundle(
                at: CollegeModelContainerFactory.catalogStoreURL(for: expectedSchoolID)
            )
        }

        _ = try CollegeModelContainerFactory.makeCatalogContainer(schoolID: expectedSchoolID)
        AppDataStoreBridge.syncActiveCatalogSchool(universityName: "Launch Bridge U")

        let store = AppDataStore.shared
        XCTAssertEqual(store.activeCatalogSchoolID, expectedSchoolID)
        let firstContainer = try XCTUnwrap(store.activeCatalogContainer)

        AppDataStoreBridge.syncActiveCatalogSchool(universityName: "Launch Bridge U")
        XCTAssertTrue(firstContainer === store.activeCatalogContainer)
    }
}
