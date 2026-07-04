// ShellP95BudgetContractTests.swift
// Part 11 / E-21 — release p95 budget constants match program gate.

import XCTest
@testable import College

final class ShellP95BudgetContractTests: XCTestCase {
    func testReleaseShellSidebarBudget_is100ms() {
        XCTAssertEqual(LaunchPerformanceAcceptance.shellSidebarToggleWarnMsRelease, 100)
    }

    func testReleaseAcademicsAuditBudget_is2s() {
        XCTAssertEqual(LaunchPerformanceAcceptance.academicsAuditWarnMsRelease, 2_000)
    }

    func testReleaseLaunchPipelineBudget_is8s() {
        XCTAssertEqual(LaunchPerformanceAcceptance.pipelineWallClockWarnMsRelease, 8_000)
    }

    func testShellPerformanceTiming_emitsDiagnosticsOnSlowSidebar() {
        let path = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("College/Debug/Diagnostics/ShellPerformanceTiming.swift")
        let source = try? String(contentsOf: path, encoding: .utf8)
        XCTAssertNotNil(source)
        XCTAssertTrue(source?.contains("shellSidebarToggleExceedsBudget") == true)
    }
}
