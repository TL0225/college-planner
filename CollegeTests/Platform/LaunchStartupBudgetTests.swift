// LaunchStartupBudgetTests.swift
// Validates startup lane budget error propagation.

import XCTest
@testable import College

final class LaunchStartupBudgetTests: XCTestCase {
    func testRunPropagatesOperationError() async {
        struct TestLaneError: Error {}

        do {
            _ = try await LaunchStartupBudget.shared.run(lane: .database) {
                throw TestLaneError()
            }
            XCTFail("Expected LaunchStartupBudget.run to rethrow")
        } catch is TestLaneError {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
