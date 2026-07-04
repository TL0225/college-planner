// AppActivityCoordinatorThrottleTests.swift
// Validates inactive throttle stagger matches the 1.2s resume budget.

import XCTest
@testable import College

@MainActor
final class AppActivityCoordinatorThrottleTests: XCTestCase {
    override func setUp() {
        UserDefaults.standard.set(true, forKey: AppActivityCoordinator.inactiveStateEnabledKey)
        AppActivityCoordinator.shared._testingResetToActive()
    }

    override func tearDown() {
        AppActivityCoordinator.shared._testingResetToActive()
    }

    func testInactiveSetsThrottleImmediately() {
        let coordinator = AppActivityCoordinator.shared
        coordinator.handleScenePhase(.inactive)
        XCTAssertTrue(coordinator.isResourceThrottled)
        XCTAssertTrue(coordinator.shouldApplyInactiveDim)
    }

    func testActiveClearsThrottleAfterStaggerBudget() async {
        let coordinator = AppActivityCoordinator.shared
        coordinator.handleScenePhase(.inactive)
        XCTAssertTrue(coordinator.isResourceThrottled)

        coordinator.handleScenePhase(.active)
        XCTAssertFalse(coordinator.shouldApplyInactiveDim)
        XCTAssertTrue(coordinator.isResourceThrottled, "Throttle should remain during stagger window")

        try? await Task.sleep(nanoseconds: 1_250_000_000)
        XCTAssertFalse(coordinator.isResourceThrottled, "Throttle should clear within 1.2s stagger budget")
    }
}
