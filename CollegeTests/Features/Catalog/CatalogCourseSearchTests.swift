// CatalogCourseSearchTests.swift
// Feature: Catalog
// Purpose: Catalog module — CatalogCourseSearchTests.
// Data: CollegePersistence / repositories when applicable.

import XCTest
@testable import College

@MainActor
final class CatalogCourseSearchTests: XCTestCase {
    func testQueryLooksLikeCourseCode() {
        XCTAssertTrue(CatalogCourseCodeHelpers.queryLooksLikeCourseCode("MATH-UA"))
        XCTAssertTrue(CatalogCourseCodeHelpers.queryLooksLikeCourseCode("ACCT-UB 1"))
        XCTAssertFalse(CatalogCourseCodeHelpers.queryLooksLikeCourseCode("biology"))
        XCTAssertFalse(CatalogCourseCodeHelpers.queryLooksLikeCourseCode("a"))
    }

    func testCompactCatalogCourseCode() {
        XCTAssertEqual(CatalogCourseCodeHelpers.compactCatalogCourseCode("MATH-UA 121"), "MATHUA121")
        XCTAssertEqual(CatalogCourseCodeHelpers.compactCatalogCourseCode("math ua"), "MATHUA")
    }
}
