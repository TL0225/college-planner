// TransferNormalizationTests.swift
// Feature: Transfer / Tests
// Purpose: Dedupe key and school ID normalization tests.

import XCTest
@testable import College

final class TransferNormalizationTests: XCTestCase {
    func testDedupeKeyNormalizesCourseCodes() {
        let dto = TransferFixtureFactory.sampleDTO(sourceCode: "math 101", targetCode: "MATH 1100")
        let key = TransferNormalization.dedupeKey(for: dto)
        XCTAssertTrue(key.contains("|"))
        XCTAssertTrue(key.contains("MATH"))
    }

    func testSamePairingProducesStableKey() {
        let a = TransferNormalization.dedupeKey(for: TransferFixtureFactory.sampleDTO(sourceCode: "MATH 101"))
        let b = TransferNormalization.dedupeKey(for: TransferFixtureFactory.sampleDTO(sourceCode: "math 101"))
        XCTAssertEqual(a, b)
    }

    func testNormalizeSchoolIDStripsWhitespace() {
        XCTAssertEqual(
            TransferNormalization.normalizeSchoolID("  Example University  "),
            "example_university"
        )
    }
}
