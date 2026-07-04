// CatalogSyncProgressReporterTests.swift
// Feature: Catalog
// Purpose: Terminal transition coverage for CatalogSyncProgressReporter.

import XCTest
@testable import College

@MainActor
final class CatalogSyncProgressReporterTests: XCTestCase {
    override func setUp() {
        super.setUp()
        BackgroundActivityCenter.shared.resetForTesting()
        BackgroundActivityCenter.shared.startObservingProgressNotifications()
    }

    override func tearDown() {
        BackgroundActivityCenter.shared.resetForTesting()
        CatalogSyncProgressReporter.endSession()
        super.tearDown()
    }

    func testSucceededTerminalFinishesMainCatalogActivity() {
        CatalogSyncProgressReporter.main.reportTerminal(
            .succeeded(summary: "Programs saved")
        )

        let activity = BackgroundActivityCenter.shared.activities.first {
            $0.id == BackgroundActivityCenter.catalogImportID
        }
        XCTAssertNotNil(activity)
        if case .succeeded(let summary) = activity?.phase {
            XCTAssertEqual(summary, "Programs saved")
        } else {
            XCTFail("Expected succeeded terminal on catalog.import")
        }
    }

    func testSkippedTerminalDoesNotMarkFailed() {
        CatalogSyncProgressReporter.main.reportTerminal(
            .skipped(reason: "Catalog unchanged")
        )

        let activity = BackgroundActivityCenter.shared.activities.first {
            $0.id == BackgroundActivityCenter.catalogImportID
        }
        XCTAssertNotNil(activity)
        if case .succeeded(let summary) = activity?.phase {
            XCTAssertEqual(summary, "Catalog unchanged")
        } else {
            XCTFail("Expected skipped to map to succeeded-style terminal copy")
        }
    }

    func testFailedTerminalMarksActivityFailed() {
        CatalogSyncProgressReporter.main.reportTerminal(
            .failed(message: "Network error")
        )

        let activity = BackgroundActivityCenter.shared.activities.first {
            $0.id == BackgroundActivityCenter.catalogImportID
        }
        XCTAssertNotNil(activity)
        if case .failed(let message) = activity?.phase {
            XCTAssertEqual(message, "Network error")
        } else {
            XCTFail("Expected failed terminal on catalog.import")
        }
    }

    func testCoursesActivityUsesSeparateID() {
        CatalogSyncProgressReporter.courses.reportTerminal(
            .failed(message: "Phase B failed")
        )

        let main = BackgroundActivityCenter.shared.activities.first {
            $0.id == BackgroundActivityCenter.catalogImportID
        }
        XCTAssertNil(main)

        let courses = BackgroundActivityCenter.shared.activities.first {
            $0.id == BackgroundActivityCenter.catalogCoursesID
        }
        XCTAssertNotNil(courses)
        if case .failed(let message) = courses?.phase {
            XCTAssertEqual(message, "Phase B failed")
        } else {
            XCTFail("Expected failed terminal on catalog.courses")
        }
    }

    func testPhaseACommittedFiresHook() {
        let universityID = UUID()
        var committedID: UUID?
        var committedCount = 0

        let hooks = CatalogBackgroundSyncRunner.Hooks(
            onPhaseACommitted: { id, count in
                committedID = id
                committedCount = count
            }
        )
        CatalogSyncProgressReporter.beginSession(hooks: hooks)
        CatalogSyncProgressReporter.emitPhaseACommitted(universityID: universityID, programCount: 42)

        XCTAssertEqual(committedID, universityID)
        XCTAssertEqual(committedCount, 42)
    }

    func testCatalogSyncProgressMapsSkippedNotification() {
        let progress = CatalogSyncProgress.fromNotificationUserInfo([
            "finished": true,
            "skipped": true,
            "title": "Already up to date",
        ])

        XCTAssertEqual(progress?.phase, .skipped)
        XCTAssertEqual(progress?.detail, "Already up to date")
    }

    func testCatalogSyncProgressMapsReporterSnapshot() {
        let progress = CatalogSyncProgress.fromNotificationUserInfo([
            "phase": CatalogSyncProgress.Phase.indexing.rawValue,
            "completed": 12,
            "total": 40,
            "unit": CatalogSyncProgress.Unit.chunks.rawValue,
            "detail": "Indexing vectors",
            "activityID": BackgroundActivityCenter.catalogVectorIndexID,
        ])

        XCTAssertEqual(progress?.phase, .indexing)
        XCTAssertEqual(progress?.completed, 12)
        XCTAssertEqual(progress?.total, 40)
        XCTAssertEqual(progress?.unit, .chunks)
        XCTAssertEqual(progress?.detail, "Indexing vectors")
    }
}
