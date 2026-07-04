// ResumeATSDatesTests.swift
// Feature: Resume Tests
// Purpose: ATS date normalization for apply payloads.

import XCTest
@testable import College

final class ResumeATSDatesTests: XCTestCase {
    func testPresentTokenNormalizedInRange() {
        XCTAssertEqual(
            ResumeATSDates.normalizeRangeForATS("Jan 2024 – current"),
            "01/2024 – Present"
        )
    }

    func testStandalonePresentToken() {
        XCTAssertEqual(ResumeATSDates.normalizeForATS("Current"), "Present")
    }

    func testMonthYearTokenNormalized() {
        XCTAssertEqual(ResumeATSDates.normalizeForATS("September 2023"), "09/2023")
    }

    func testEmptyReturnsNil() {
        XCTAssertNil(ResumeATSDates.normalizeForATS("   "))
        XCTAssertNil(ResumeATSDates.normalizeForATS(nil))
    }

    func testRangeUsesEnDash() {
        let normalized = ResumeATSDates.normalizeRangeForATS("Jan 2022 - Dec 2023")
        XCTAssertTrue(normalized?.contains("–") == true)
    }
}
