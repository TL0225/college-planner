// CatalogPDFExtractorSafetyTests.swift
// Snow Leopard V&V: garbage PDF text does not trap (Q4).

import XCTest
@testable import College

final class CatalogPDFExtractorSafetyTests: XCTestCase {
    func testGarbageSectionTextReturnsEmptyRequirements() {
        let garbage = String(repeating: "\u{FFFD}", count: 4096)
        let requirements = CatalogPDFRequirementExtractor.extractRequirements(
            sectionText: garbage,
            knownPrograms: [],
            courseCatalog: []
        )
        XCTAssertTrue(requirements.isEmpty)
    }

    func testEmptySectionTextReturnsEmptyRequirements() {
        let requirements = CatalogPDFRequirementExtractor.extractRequirements(
            sectionText: "",
            knownPrograms: [ScrapedProgram(name: "History", type: "Major", url: "pdf://test")],
            courseCatalog: []
        )
        XCTAssertTrue(requirements.isEmpty)
    }
}
