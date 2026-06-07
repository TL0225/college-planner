// ModernCampusIRPipelineTests.swift
// Feature: Catalog
// Purpose: Offline Modern Campus IR pipeline — layout profile + program extraction.

import XCTest
@testable import College

final class ModernCampusIRPipelineTests: XCTestCase {
    func testParsePage_extractsPreviewProgramLinks() throws {
        let fixtureURL = try TestFixturePaths.url("ModernCampus/program_listing_snippet.html")
        let html = try String(contentsOf: fixtureURL, encoding: .utf8)
        let pageURL = try XCTUnwrap(URL(string: "https://catalogs.example.edu/content.php?catoid=17&navoid=1040"))

        let result = ModernCampusIRPipeline.parsePage(
            html: html,
            pageURL: pageURL,
            schoolID: "example_university",
            catalogVersionID: "example_university|mc|17"
        )

        XCTAssertFalse(result.ir.layoutProfileID.isEmpty)
        XCTAssertGreaterThan(result.ir.layoutConfidence.score, 0)
        let names = Set(result.programs.map(\.name))
        XCTAssertTrue(names.contains("Computer Science BS"))
        XCTAssertTrue(names.contains("Mathematics BA"))
        XCTAssertTrue(names.contains("Physics BS"))
        XCTAssertTrue(result.programs.allSatisfy { $0.url.contains("preview_program") })
    }
}
