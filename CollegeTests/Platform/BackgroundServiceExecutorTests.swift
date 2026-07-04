// BackgroundServiceExecutorTests.swift
// Architecture gate: executor isolation and failure containment.

import Darwin
import XCTest
@testable import College

@MainActor
final class BackgroundServiceExecutorTests: XCTestCase {
    func testFetchOffMainRunsOffMainThread() async throws {
        let ranOffMain = try await BackgroundServiceExecutor.fetchOffMain {
            pthread_main_np() == 0
        }
        XCTAssertTrue(ranOffMain)
    }

    func testRunWorkUnitContainsFailureWithoutRethrow() async {
        struct TestError: Error {}
        var failureCalled = false

        await BackgroundServiceExecutor.runWorkUnit(
            serviceID: "test_executor_failure",
            operation: {
                throw TestError()
            },
            onFailure: { _ in
                failureCalled = true
            }
        )

        XCTAssertTrue(failureCalled)
    }

    func testRunWorkUnitSuccessDoesNotInvokeOnFailure() async {
        var failureCalled = false

        await BackgroundServiceExecutor.runWorkUnit(
            serviceID: "test_executor_success",
            operation: { },
            onFailure: { _ in
                failureCalled = true
            }
        )

        XCTAssertFalse(failureCalled)
    }
}
