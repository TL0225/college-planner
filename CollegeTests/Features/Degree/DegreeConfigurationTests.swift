// DegreeConfigurationTests.swift
// Feature: Degree
// Purpose: Canonical degree-level mapping for catalog picker labels.

import XCTest
@testable import College

final class DegreeConfigurationTests: XCTestCase {
    func testCanonicalLevel_mapsModernCampusPostedCatalogTitles() {
        XCTAssertEqual(
            DegreeConfiguration.canonicalLevel("Graduate Catalog 2025-2026"),
            DegreeConfiguration.graduate
        )
        XCTAssertEqual(
            DegreeConfiguration.canonicalLevel("Undergraduate Catalog 2025-2026"),
            DegreeConfiguration.undergraduate
        )
    }

    func testQueryLevels_expandsGraduateCatalogTitleAgainstStoredLevels() {
        let levels = DegreeConfiguration.queryLevels(
            for: "Graduate Catalog 2025-2026",
            availableLevels: ["Graduate", "Undergraduate"]
        )
        XCTAssertTrue(levels.contains(DegreeConfiguration.graduate))
    }
}
