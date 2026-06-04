// DataWipeStoreTests.swift
// Feature: Shared
// Purpose: Shared module — DataWipeStoreTests.
// Data: CollegePersistence / repositories when applicable.

import XCTest
@testable import College

@MainActor
final class DataWipeStoreTests: XCTestCase {
    func testRemoveAllOnDiskStores_clearsProfileAndCatalogSQLite() throws {
        let profileURL = ModelStoreMaintenance.profileStoreURL()
        let schoolID = "wipe_test_school_\(UUID().uuidString.prefix(8))"
        let catalogURL = CollegeModelContainerFactory.catalogStoreURL(for: schoolID)

        _ = try CollegeModelContainerFactory.makeProfileContainer()
        _ = try CollegeModelContainerFactory.makeCatalogContainer(schoolID: schoolID)

        let fm = FileManager.default
        XCTAssertTrue(fm.fileExists(atPath: profileURL.path))
        XCTAssertTrue(fm.fileExists(atPath: catalogURL.path))

        ModelStoreMaintenance.removeAllOnDiskStores()
        ModelStoreMaintenance.removeSQLiteBundle(at: catalogURL)

        XCTAssertFalse(fm.fileExists(atPath: profileURL.path))
        XCTAssertFalse(fm.fileExists(atPath: catalogURL.path))
        XCTAssertFalse(fm.fileExists(atPath: profileURL.appendingPathExtension("-wal").path))
        XCTAssertFalse(fm.fileExists(atPath: catalogURL.appendingPathExtension("-shm").path))
    }
}
