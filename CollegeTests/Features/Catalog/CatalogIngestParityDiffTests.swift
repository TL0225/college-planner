// CatalogIngestParityDiffTests.swift
// Feature: Shared
// Purpose: Offline legacy vs IR entity-set parity for frozen CourseLeaf fixtures.
// Data: CollegePersistence / repositories when applicable.

import XCTest
@testable import College

final class CatalogIngestParityDiffTests: XCTestCase {
    func testFordhamFixture_legacyAndIRParity() throws {
        let xmlURL = try XCTUnwrap(
            Bundle(for: type(of: self)).url(
                forResource: "fordham_aast_courses",
                withExtension: "xml",
                subdirectory: "Fixtures/CourseLeaf"
            )
        )
        let xml = try String(contentsOf: xmlURL, encoding: .utf8)
        let pageURL = URL(string: "https://bulletin.fordham.edu/undergraduate/african-american-studies/courses/")!
        let report = CatalogIngestParityDiff.compareFixture(
            xml: xml,
            pageURL: pageURL,
            schoolID: "fordham_university"
        )
        XCTAssertTrue(report.isParity, "parity diff: legacy-only courses=\(report.coursesOnlyInLegacy) ir-only=\(report.coursesOnlyInIR) legacy programs=\(report.programsOnlyInLegacy) ir-only=\(report.programsOnlyInIR)")
    }
}
