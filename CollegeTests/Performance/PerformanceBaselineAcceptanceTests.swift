// PerformanceBaselineAcceptanceTests.swift
// Feature: Shared
// Purpose: Shared module — PerformanceBaselineAcceptanceTests.
// Data: CollegePersistence / repositories when applicable.

import XCTest
@testable import College

final class PerformanceBaselineAcceptanceTests: XCTestCase {

    // MARK: - Academics audit

    func testAcademicsAuditBudget_notExceededForSmallDuration() {
        XCTAssertFalse(LaunchPerformanceAcceptance.academicsAuditDurationExceedsBudget(durationMs: 100))
        XCTAssertFalse(LaunchPerformanceAcceptance.academicsAuditDurationExceedsBudget(durationMs: 0))
    }

    func testAcademicsAuditBudget_exceededBeyondThreshold() {
        XCTAssertTrue(
            LaunchPerformanceAcceptance.academicsAuditDurationExceedsBudget(
                durationMs: LaunchPerformanceAcceptance.academicsAuditWarnThresholdMs + 1
            )
        )
    }

    func testAcademicsAuditThreshold_matchesDebugOrReleaseExpectation() {
        #if DEBUG
        XCTAssertEqual(LaunchPerformanceAcceptance.academicsAuditWarnThresholdMs, 10_000)
        #else
        XCTAssertEqual(LaunchPerformanceAcceptance.academicsAuditWarnThresholdMs, 3_000)
        #endif
    }

    // MARK: - Resident memory

    func testResidentMemoryBudget_notExceededAtThreshold() {
        for scenario in LaunchPerformanceAcceptance.ResidentMemoryScenario.allCases {
            let threshold = LaunchPerformanceAcceptance.residentMemoryWarnThresholdMB(for: scenario)
            XCTAssertFalse(
                LaunchPerformanceAcceptance.residentMemoryExceedsBudget(residentMB: threshold, scenario: scenario),
                "At-threshold RSS should not exceed budget for \(scenario)"
            )
        }
    }

    func testResidentMemoryBudget_exceededBeyondThreshold() {
        for scenario in LaunchPerformanceAcceptance.ResidentMemoryScenario.allCases {
            let threshold = LaunchPerformanceAcceptance.residentMemoryWarnThresholdMB(for: scenario)
            XCTAssertTrue(
                LaunchPerformanceAcceptance.residentMemoryExceedsBudget(residentMB: threshold + 1, scenario: scenario),
                "RSS above threshold should exceed budget for \(scenario)"
            )
        }
    }

    func testColdLaunchResidentMemoryThreshold_matchesDebugOrReleaseExpectation() {
        #if DEBUG
        XCTAssertEqual(
            LaunchPerformanceAcceptance.residentMemoryWarnThresholdMB(for: .coldLaunch),
            LaunchPerformanceAcceptance.coldLaunchResidentMemoryWarnMBDebug
        )
        #else
        XCTAssertEqual(
            LaunchPerformanceAcceptance.residentMemoryWarnThresholdMB(for: .coldLaunch),
            LaunchPerformanceAcceptance.coldLaunchResidentMemoryWarnMBRelease
        )
        #endif
    }

    func testVectorReindexResidentMemoryThreshold_matchesDebugOrReleaseExpectation() {
        #if DEBUG
        XCTAssertEqual(
            LaunchPerformanceAcceptance.residentMemoryWarnThresholdMB(for: .vectorReindex),
            LaunchPerformanceAcceptance.vectorReindexResidentMemoryWarnMBDebug
        )
        #else
        XCTAssertEqual(
            LaunchPerformanceAcceptance.residentMemoryWarnThresholdMB(for: .vectorReindex),
            LaunchPerformanceAcceptance.vectorReindexResidentMemoryWarnMBRelease
        )
        #endif
    }

    // MARK: - Shell navigation

    func testShellPageSwitchBudget_notExceededAtThreshold() {
        XCTAssertFalse(
            LaunchPerformanceAcceptance.shellPageSwitchExceedsBudget(
                durationMs: LaunchPerformanceAcceptance.shellPageSwitchWarnThresholdMs
            )
        )
    }

    func testShellPageSwitchBudget_exceededBeyondThreshold() {
        XCTAssertTrue(
            LaunchPerformanceAcceptance.shellPageSwitchExceedsBudget(
                durationMs: LaunchPerformanceAcceptance.shellPageSwitchWarnThresholdMs + 1
            )
        )
    }

    func testShellInspectorToggleBudget_matchesDebugOrReleaseExpectation() {
        #if DEBUG
        XCTAssertEqual(LaunchPerformanceAcceptance.shellInspectorToggleWarnThresholdMs, 1_000)
        #else
        XCTAssertEqual(LaunchPerformanceAcceptance.shellInspectorToggleWarnThresholdMs, 350)
        #endif
    }
}
