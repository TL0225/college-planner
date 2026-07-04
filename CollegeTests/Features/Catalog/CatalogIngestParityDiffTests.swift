// CatalogIngestParityDiffTests.swift
// Feature: Shared
// Purpose: Offline legacy vs IR entity-set parity for frozen CourseLeaf fixtures.
// Data: CollegePersistence / repositories when applicable.

import XCTest
@testable import College

final class CatalogIngestParityDiffTests: XCTestCase {
    func testFordhamFixture_legacyAndIRParity() throws {
        let xml = try TestFixturePaths.courseLeafString(named: "fordham_aast_courses.xml")
        let pageURL = URL(string: "https://bulletin.fordham.edu/undergraduate/african-american-studies/courses/")!
        let report = CatalogIngestParityDiff.compareFixture(
            xml: xml,
            pageURL: pageURL,
            schoolID: "fordham_university"
        )
        XCTAssertTrue(report.isParity, "parity diff: legacy-only courses=\(report.coursesOnlyInLegacy) ir-only=\(report.coursesOnlyInIR) legacy programs=\(report.programsOnlyInLegacy) ir-only=\(report.programsOnlyInIR)")
    }
}
