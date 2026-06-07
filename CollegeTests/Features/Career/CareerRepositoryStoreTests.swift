// CareerRepositoryStoreTests.swift
// Feature: Career
// Purpose: Career module — CareerRepositoryStoreTests.
// Data: CollegePersistence / repositories when applicable.

import SwiftData
import XCTest
@testable import College

final class CareerRepositoryStoreTests: PersistenceTestCase {
    func testFetchApplicationsAndEvents() throws {
        let application = JobApplication(statusRaw: "applied", sortOrder: 1)
        application.title = "Engineer"
        application.company = "Acme"

        let event = CareerEvent()
        event.title = "Phone screen"
        event.date = Date()
        event.application = application

        profileContext.insert(application)
        profileContext.insert(event)
        try profileContext.save()

        let repo = CareerRepository(context: profileContext)
        XCTAssertEqual(try repo.fetchApplications(limit: 10).count, 1)
        XCTAssertEqual(try repo.fetchUpcomingEvents(limit: 10).count, 1)
    }

    func testModelStoreMaintenanceRemoveProfileBundle() throws {
        let url = ModelStoreMaintenance.profileStoreURL()
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        fm.createFile(atPath: url.path, contents: Data("test".utf8))
        fm.createFile(atPath: url.appendingPathExtension("-wal").path, contents: Data())
        XCTAssertTrue(fm.fileExists(atPath: url.path))

        ModelStoreMaintenance.removeSQLiteBundle(at: url)
        XCTAssertFalse(fm.fileExists(atPath: url.path))
        XCTAssertFalse(fm.fileExists(atPath: url.appendingPathExtension("-wal").path))
    }
}
