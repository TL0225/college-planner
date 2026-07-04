// OnboardingHandoffCommitTests.swift
// Feature: Catalog
// Purpose: Behavioral contract for FTUE handoff after Phase A catalog commit.

import XCTest
@testable import College

@MainActor
final class OnboardingHandoffCommitTests: XCTestCase {
    /// Mirrors OnboardingRootView: handoff unlocks when phase-A commit fires with programs saved.
    func testPhaseACommitWithProgramsEnablesHandoff() {
        let expectation = expectation(description: "phaseA committed")
        let token = NotificationCenter.default.addObserver(
            forName: .catalogSyncPhaseACommitted,
            object: nil,
            queue: .main
        ) { note in
            let programCount = note.userInfo?["programCount"] as? Int ?? 0
            XCTAssertGreaterThan(programCount, 0)
            expectation.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(token) }

        let universityID = UUID()
        CatalogSyncProgressReporter.emitPhaseACommitted(universityID: universityID, programCount: 24)

        wait(for: [expectation], timeout: 1)
    }

    func testPhaseACommitWithZeroProgramsDoesNotSatisfyHandoffGate() {
        var receivedCount: Int?
        let token = NotificationCenter.default.addObserver(
            forName: .catalogSyncPhaseACommitted,
            object: nil,
            queue: .main
        ) { note in
            receivedCount = note.userInfo?["programCount"] as? Int
        }
        defer { NotificationCenter.default.removeObserver(token) }

        CatalogSyncProgressReporter.emitPhaseACommitted(universityID: UUID(), programCount: 0)

        XCTAssertEqual(receivedCount, 0)
        // OnboardingRootView ignores programCount == 0 for handoffReady.
        XCTAssertFalse((receivedCount ?? 0) > 0)
    }

    func testIngestPipelinePhaseACommitIncludesUniversityID() {
        let universityID = UUID()
        let expectation = expectation(description: "catalogDataDidCommit phaseA")
        let token = NotificationCenter.default.addObserver(
            forName: .catalogDataDidCommit,
            object: nil,
            queue: .main
        ) { note in
            XCTAssertEqual(note.userInfo?["universityID"] as? String, universityID.uuidString)
            XCTAssertEqual(
                note.userInfo?["commitPhase"] as? String,
                CatalogIngestPipeline.CommitPhase.phaseA.rawValue
            )
            expectation.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(token) }

        CatalogIngestPipeline.postCatalogDataDidCommit(
            universityID: universityID,
            reason: "onboarding handoff test",
            commitPhase: .phaseA,
            programCount: 10,
            schoolID: "dakota_state_university"
        )

        wait(for: [expectation], timeout: 1)
    }
}
