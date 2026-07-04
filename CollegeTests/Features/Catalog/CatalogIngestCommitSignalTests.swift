// CatalogIngestCommitSignalTests.swift
// Feature: Catalog
// Purpose: Notification contract for catalogDataDidCommit handoff signals.

import XCTest
@testable import College

@MainActor
final class CatalogIngestCommitSignalTests: XCTestCase {
    func testPostCatalogDataDidCommitIncludesPhaseAFields() {
        let universityID = UUID()
        let schoolID = "dakota_state_university"
        let expectation = expectation(description: "catalogDataDidCommit")
        let token = NotificationCenter.default.addObserver(
            forName: .catalogDataDidCommit,
            object: nil,
            queue: .main
        ) { notification in
            let info = notification.userInfo ?? [:]
            XCTAssertEqual(info["universityID"] as? String, universityID.uuidString)
            XCTAssertEqual(info["schoolID"] as? String, schoolID)
            XCTAssertEqual(info["commitPhase"] as? String, CatalogIngestPipeline.CommitPhase.phaseA.rawValue)
            XCTAssertEqual(info["programCount"] as? Int, 128)
            XCTAssertEqual(info["reason"] as? String, "test phaseA commit")
            expectation.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(token) }

        CatalogIngestPipeline.postCatalogDataDidCommit(
            universityID: universityID,
            reason: "test phaseA commit",
            commitPhase: .phaseA,
            programCount: 128,
            schoolID: schoolID
        )

        wait(for: [expectation], timeout: 1)
    }

    func testPostCatalogDataDidCommitPhaseBOmittedWhenNil() {
        let universityID = UUID()
        let expectation = expectation(description: "catalogDataDidCommit phaseB")
        let token = NotificationCenter.default.addObserver(
            forName: .catalogDataDidCommit,
            object: nil,
            queue: .main
        ) { notification in
            let info = notification.userInfo ?? [:]
            XCTAssertEqual(info["commitPhase"] as? String, CatalogIngestPipeline.CommitPhase.phaseB.rawValue)
            expectation.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(token) }

        CatalogIngestPipeline.postCatalogDataDidCommit(
            universityID: universityID,
            reason: "phaseB",
            commitPhase: .phaseB,
            programCount: 0
        )

        wait(for: [expectation], timeout: 1)
    }
}
