// ModernCampusCatalogDiscoveryTests.swift
// Feature: Catalog
// Purpose: Shared discovery resolver behavior (offline).

import XCTest
@testable import College

final class ModernCampusCatalogDiscoveryTests: XCTestCase {
    func testMergeProgramsAcrossCatalogs_dedupesByCatoidAndURL() {
        let program = ScrapedProgram(
            name: "Computer Science",
            type: "Major",
            url: "https://catalog.example.edu/preview_program.php?catoid=1&poid=10"
        )
        let merged = ModernCampusCatalogDiscovery.mergeProgramsAcrossCatalogs([
            (catoid: "10", programs: [program]),
            (catoid: "11", programs: [program]),
        ])
        XCTAssertEqual(merged.count, 2)

        let collapsed = ModernCampusCatalogDiscovery.mergeProgramsAcrossCatalogs([
            (catoid: "10", programs: [program]),
            (catoid: "10", programs: [program]),
        ])
        XCTAssertEqual(collapsed.count, 1)
    }

    func testMergeProgramsAcrossCatalogs_usesNameWhenURLMissing() {
        let program = ScrapedProgram(name: "Undeclared Major", type: "Major", url: "")
        let merged = ModernCampusCatalogDiscovery.mergeProgramsAcrossCatalogs([
            (catoid: "7", programs: [program]),
            (catoid: "7", programs: [program]),
        ])
        XCTAssertEqual(merged.count, 1)
    }
}
