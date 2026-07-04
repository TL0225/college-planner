// CatalogScrapedProgramDedupTests.swift
// Feature: Catalog
// Purpose: Early ingest dedup aligns gate metrics with persisted rows.

import XCTest
@testable import College

final class CatalogScrapedProgramDedupTests: XCTestCase {
    func testCollapseByCanonicalMajor_keepsMostSpecificRow() {
        let generic = ScrapedProgram(
            name: "Computer Science",
            type: "Major",
            url: "https://catalog.example.edu/preview_program.php?poid=1"
        )
        let specific = ScrapedProgram(
            name: "Computer Science",
            type: "Major",
            url: "https://catalog.example.edu/preview_program.php?poid=2",
            department: "Computer Science",
            degreeType: "BS"
        )
        let input: [String: ScrapedProgram] = [
            "17|https://catalog.example.edu/preview_program.php?poid=1": generic,
            "17|https://catalog.example.edu/preview_program.php?poid=2": specific,
        ]

        let collapsed = CatalogScrapedProgramDedup.collapseByCanonicalMajor(input)
        XCTAssertEqual(collapsed.count, 1)
        XCTAssertEqual(collapsed.values.first?.name, "Computer Science")
        XCTAssertEqual(collapsed.values.first?.degreeType, "BS")
    }
}
