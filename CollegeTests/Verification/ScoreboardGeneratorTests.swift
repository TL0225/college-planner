// ScoreboardGeneratorTests.swift
// Snow Leopard V&V: scoreboard JSON fields are populated.

import XCTest
@testable import College

@MainActor
final class ScoreboardGeneratorTests: XCTestCase {
    func testHealthMetricsSnapshotEncodes() throws {
        SnowLeopardHealthMetrics.recordRefreshProfileCaches()
        let snapshot = SnowLeopardHealthMetrics.snapshot()
        let data = try JSONEncoder().encode(snapshot)
        XCTAssertFalse(data.isEmpty)
        XCTAssertNotNil(snapshot.capturedAt)
    }
}
