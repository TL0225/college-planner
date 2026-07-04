// FTUEPathContractTests.swift
// Part 20 / E-90 — five-minute FTUE path instrumentation contract.

import XCTest

final class FTUEPathContractTests: XCTestCase {
    private let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    func testOnboardingExposesEnterWorkspaceAndStepLandmarks() throws {
        let path = repoRoot.appendingPathComponent("College/App/OnboardingRootView.swift")
        let source = try String(contentsOf: path, encoding: .utf8)
        XCTAssertTrue(source.contains("Enter Workspace"))
        XCTAssertTrue(source.contains("onboarding.step."))
        XCTAssertTrue(source.contains("onboardingCompleted"))
    }

    func testOnboardingHandoffUsesPhaseACommitSignal() throws {
        let path = repoRoot.appendingPathComponent("College/App/OnboardingRootView.swift")
        let source = try String(contentsOf: path, encoding: .utf8)
        XCTAssertTrue(source.contains(".catalogSyncPhaseACommitted"))
        XCTAssertFalse(source.contains("onPhaseACommitted: {"))
    }

    func testProductAnalyticsCoversFTUEAndFunnelEvents() throws {
        let path = repoRoot.appendingPathComponent("College/Core/Services/ProductAnalytics.swift")
        let source = try String(contentsOf: path, encoding: .utf8)
        for event in ["onboardingCompleted", "ftueStepCompleted", "courseAdded", "resumeExported", "pageVisited"] {
            XCTAssertTrue(source.contains(event), "Missing analytics event \(event)")
        }
    }
}
