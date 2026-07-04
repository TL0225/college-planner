// CatalogVerificationSampleSelectionTests.swift
// Feature: Catalog
// Purpose: Offline checks for live-suite sample program ranking.

import XCTest
@testable import College

final class CatalogVerificationSampleSelectionTests: XCTestCase {
    func testRankedCandidates_prefersMajorOverMinor() {
        let programs = [
            ScrapedProgram(name: "American Politics Minor", type: "Minor", url: "https://example.edu/minor/"),
            ScrapedProgram(name: "Computer Science B.S.", type: "Major", url: "https://example.edu/cs/"),
            ScrapedProgram(name: "Accounting Certificate", type: "Certificate", url: "https://example.edu/cert/")
        ]

        let ranked = CatalogVerificationSampleSelection.rankedCandidates(from: programs)
        XCTAssertEqual(ranked.first?.name, "Computer Science B.S.")
        XCTAssertEqual(ranked.last?.name, "American Politics Minor")
    }

    func testRankedCandidates_filtersProgramsWithoutURLs() {
        let programs = [
            ScrapedProgram(name: "No URL Major", type: "Major", url: "   "),
            ScrapedProgram(name: "Valid Major", type: "Major", url: "https://example.edu/major/")
        ]
        let ranked = CatalogVerificationSampleSelection.rankedCandidates(from: programs)
        XCTAssertEqual(ranked.count, 1)
        XCTAssertEqual(ranked.first?.name, "Valid Major")
    }
}
