// LoadOperationTraceTests.swift
// Feature: Performance tests
// Purpose: Verify load-operation tracing records duration and metadata.

import XCTest
@testable import College

final class LoadOperationTraceTests: XCTestCase {
    func testWithSpanRecordsDurationAndName() async throws {
        await LoadOperationRecorder.shared.clear()

        _ = try await LoadOperationTrace.withSpan(
            name: "test.span",
            category: .general,
            metadata: ["fixture": "true"]
        ) {
            try await Task.sleep(nanoseconds: 30_000_000)
            return 42
        }

        let records = await LoadOperationTrace.recent(limit: 5)
        let match = records.last { $0.name == "test.span" }
        XCTAssertNotNil(match)
        XCTAssertEqual(match?.category, .general)
        XCTAssertGreaterThanOrEqual(match?.durationMs ?? 0, 20)
        XCTAssertEqual(match?.metadata["fixture"], "true")
        XCTAssertTrue(match?.succeeded == true)
    }

    func testRecordCompletedHonorsBudget() async {
        await LoadOperationRecorder.shared.clear()

        await LoadOperationTrace.recordCompleted(
            name: "test.budget",
            category: .launch,
            durationMs: 9_999,
            budgetMs: 100,
            executionContext: .mainThread
        )

        let records = await LoadOperationTrace.recent(limit: 3)
        let match = records.last { $0.name == "test.budget" }
        XCTAssertEqual(match?.exceededBudget, true)
        XCTAssertEqual(match?.budgetMs, 100)
    }
}
