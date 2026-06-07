// CatalogEntityLLMValidatorTests.swift
// Feature: Shared
// Purpose: Auto-validation gating (no model invocation).

import XCTest
@testable import College

final class CatalogEntityLLMValidatorTests: XCTestCase {
    override func tearDown() {
        CatalogPlatformFlags.entityLLMEnabled = false
        super.tearDown()
    }

    func testScheduleAutoValidation_skipsWhenDisabled() {
        CatalogPlatformFlags.entityLLMEnabled = false
        let snapshot = CatalogReviewSnapshot.from(
            schoolID: "test",
            reason: "low confidence program",
            severity: .warning,
            metrics: nil,
            messages: ["sanity fail"]
        )
        CatalogEntityLLMValidator.scheduleAutoValidation(
            schoolID: "test",
            reason: "low confidence program",
            severity: .warning,
            confidence: 0.3,
            snapshot: snapshot
        )
        XCTAssertNil(CatalogEntityLLMValidationStore.load(snapshotID: snapshot.id))
    }

    func testScheduleAutoValidation_skipsHighConfidence() {
        CatalogPlatformFlags.entityLLMEnabled = true
        let snapshot = CatalogReviewSnapshot.from(
            schoolID: "test",
            reason: "ok",
            severity: .warning,
            metrics: nil
        )
        CatalogEntityLLMValidator.scheduleAutoValidation(
            schoolID: "test",
            reason: "ok",
            severity: .warning,
            confidence: 0.9,
            snapshot: snapshot
        )
        XCTAssertNil(CatalogEntityLLMValidationStore.load(snapshotID: snapshot.id))
    }
}
