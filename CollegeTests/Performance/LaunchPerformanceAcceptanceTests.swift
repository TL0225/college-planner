// LaunchPerformanceAcceptanceTests.swift
// Feature: Shared
// Purpose: Shared module — LaunchPerformanceAcceptanceTests.
// Data: CollegePersistence / repositories when applicable.

import XCTest
@testable import College

final class LaunchPerformanceAcceptanceTests: XCTestCase {

    func testPipelineBudget_notExceededForSmallDuration() {
        XCTAssertFalse(LaunchPerformanceAcceptance.pipelineDurationExceedsBudget(durationMs: 500))
        XCTAssertFalse(LaunchPerformanceAcceptance.pipelineDurationExceedsBudget(durationMs: 0))
    }

    func testPipelineBudget_exceededBeyondThreshold() {
        XCTAssertTrue(
            LaunchPerformanceAcceptance.pipelineDurationExceedsBudget(
                durationMs: LaunchPerformanceAcceptance.pipelineWallClockWarnThresholdMs + 1
            )
        )
    }

    func testPipelineThreshold_matchesDebugOrReleaseExpectation() {
        #if DEBUG
        XCTAssertEqual(LaunchPerformanceAcceptance.pipelineWallClockWarnThresholdMs, LaunchPerformanceAcceptance.pipelineWallClockWarnMsDebug)
        #else
        XCTAssertEqual(LaunchPerformanceAcceptance.pipelineWallClockWarnThresholdMs, LaunchPerformanceAcceptance.pipelineWallClockWarnMsRelease)
        #endif
    }

    // MARK: - Lightweight CI gates (generous headroom for test host RSS)

    @MainActor
    func testInMemoryStoreContainer_doesNotSpikeRSSBeyondGenerousDelta() throws {
        let baselineMB = PerformanceDiagnostics.residentMemoryMB()
        _ = try CollegeModelContainerFactory.makeUnifiedInMemoryContainer()
        let afterMB = PerformanceDiagnostics.residentMemoryMB()
        let deltaMB = afterMB - baselineMB
        XCTAssertLessThan(deltaMB, 256, "In-memory V1 container should not add more than 256 MB RSS in CI")
    }

    func testProcessRSS_belowGenerousColdLaunchGateInTestHost() {
        let residentMB = Int(PerformanceDiagnostics.residentMemoryMB())
        let threshold = LaunchPerformanceAcceptance.residentMemoryWarnThresholdMB(for: .coldLaunch)
        // xcodebuild loads frameworks and may run under Debug; allow 2× budget + 512 MB slack.
        XCTAssertLessThan(
            residentMB,
            threshold * 2 + 512,
            "Test host RSS should stay within generous cold-launch gate"
        )
    }
}
