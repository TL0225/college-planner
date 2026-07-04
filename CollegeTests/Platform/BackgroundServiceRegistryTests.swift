// BackgroundServiceRegistryTests.swift
// Failure isolation: one failing descriptor must not block others.

import XCTest
import os
@testable import College

#if DEBUG
@MainActor
final class BackgroundServiceRegistryTests: XCTestCase {
    override func setUp() async throws {
        AppActivityCoordinator.shared._testingResetToActive()
        await BackgroundServiceRegistry.shared.stopAll()
    }

    override func tearDown() async throws {
        BackgroundServiceRegistry.shared._testingReplaceDescriptors(BackgroundServiceManifest.allDescriptors())
        await BackgroundServiceRegistry.shared.stopAll()
    }

    func testBootstrapStartsMultipleDescriptorsIndependently() async {
        let registry = BackgroundServiceRegistry.shared
        let firstID = "test_registry_first"
        let secondID = "test_registry_second"

        registry._testingReplaceDescriptors([
            BackgroundServiceDescriptor(
                id: firstID,
                displayName: "First",
                activation: .atLaunch,
                sortOrder: 0,
                start: { },
                stop: { }
            ),
            BackgroundServiceDescriptor(
                id: secondID,
                displayName: "Second",
                activation: .atLaunch,
                sortOrder: 1,
                start: { },
                stop: { }
            ),
        ])

        await registry.bootstrap(phase: .atLaunch)

        XCTAssertTrue(registry._testingStartedIDs.contains(firstID))
        XCTAssertTrue(registry._testingStartedIDs.contains(secondID))
    }

    func testStopAllClearsStartedState() async {
        let registry = BackgroundServiceRegistry.shared
        let id = "test_registry_stop"

        registry._testingReplaceDescriptors([
            BackgroundServiceDescriptor(
                id: id,
                displayName: "Stop Me",
                activation: .atLaunch,
                start: { },
                stop: { }
            ),
        ])

        await registry.bootstrap(phase: .atLaunch)
        XCTAssertTrue(registry._testingStartedIDs.contains(id))

        await registry.stopAll()
        XCTAssertTrue(registry._testingStartedIDs.isEmpty)
    }

    func testRegisterOnDemandDoesNotCrashForManifestID() async {
        let registry = BackgroundServiceRegistry.shared
        await registry.runOnDemand(id: "catalog_background_sync") { }
    }

    func testFailingDescriptorDoesNotBlockSiblingStart() async {
        let registry = BackgroundServiceRegistry.shared
        let failingID = "test_registry_failing_start"
        let siblingID = "test_registry_sibling_start"

        registry._testingReplaceDescriptors([
            BackgroundServiceDescriptor(
                id: failingID,
                displayName: "Failing",
                activation: .atLaunch,
                sortOrder: 0,
                start: { },
                stop: { }
            ),
            BackgroundServiceDescriptor(
                id: siblingID,
                displayName: "Sibling",
                activation: .atLaunch,
                sortOrder: 1,
                start: { },
                stop: { }
            ),
        ])
        registry._testingSetStartFailure(ids: [failingID])

        await registry.bootstrap(phase: .atLaunch)

        XCTAssertFalse(registry._testingStartedIDs.contains(failingID))
        XCTAssertTrue(registry._testingStartedIDs.contains(siblingID))
    }

    func testLaunchStartupBudgetLaneFailureDoesNotBlockSiblingStart() async {
        let registry = BackgroundServiceRegistry.shared
        let failingID = "test_registry_lane_fail"
        let siblingID = "test_registry_lane_sibling"

        registry._testingReplaceDescriptors([
            BackgroundServiceDescriptor(
                id: failingID,
                displayName: "Lane Fail",
                activation: .atLaunch,
                resourceLane: .database,
                sortOrder: 0,
                start: { },
                stop: { }
            ),
            BackgroundServiceDescriptor(
                id: siblingID,
                displayName: "Lane Sibling",
                activation: .atLaunch,
                sortOrder: 1,
                start: { },
                stop: { }
            ),
        ])
        registry._testingSetStartFailure(ids: [failingID])

        await registry.bootstrap(phase: .atLaunch)

        XCTAssertFalse(registry._testingStartedIDs.contains(failingID))
        XCTAssertTrue(registry._testingStartedIDs.contains(siblingID))
    }

    func testPauseAllAndResumeAllInvokeThrottleHandlers() async {
        let registry = BackgroundServiceRegistry.shared
        let pauseableID = "test_registry_pause_resume"
        let pauseState = PauseResumeTestState()

        registry._testingReplaceDescriptors([
            BackgroundServiceDescriptor(
                id: pauseableID,
                displayName: "Pauseable",
                activation: .atLaunch,
                throttle: .pauseWhenInactive,
                start: { pauseState.markStarted() },
                stop: { },
                pause: { pauseState.markPaused() },
                resume: { pauseState.markResumed() }
            ),
        ])

        await registry.bootstrap(phase: .atLaunch)
        XCTAssertTrue(registry._testingStartedIDs.contains(pauseableID))
        XCTAssertEqual(pauseState.startedCount, 1)

        await registry.pauseAll()
        XCTAssertEqual(pauseState.pausedCount, 1)

        await registry.resumeAll()
        XCTAssertEqual(pauseState.resumedCount, 1)
    }
}

private final class PauseResumeTestState: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: (started: 0, paused: 0, resumed: 0))

    var startedCount: Int { lock.withLock { $0.started } }
    var pausedCount: Int { lock.withLock { $0.paused } }
    var resumedCount: Int { lock.withLock { $0.resumed } }

    func markStarted() { lock.withLock { $0.started += 1 } }
    func markPaused() { lock.withLock { $0.paused += 1 } }
    func markResumed() { lock.withLock { $0.resumed += 1 } }
}
#endif
