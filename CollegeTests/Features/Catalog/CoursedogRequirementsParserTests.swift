// CoursedogRequirementsParserTests.swift
// Feature: Catalog
// Purpose: Offline requirements parsing for Coursedog program detail fixtures.

import XCTest
@testable import College

final class CoursedogRequirementsParserTests: XCTestCase {
    func testParseRequirements_ccnyFixture_extractsCoreCourses() throws {
        let html = try String(
            contentsOf: TestFixturePaths.url("Coursedog/ccny_computer_science_program.html"),
            encoding: .utf8
        )
        let baseURL = "https://ccny-undergraduate.catalog.cuny.edu/#/programs/computer-science-bs"
        let parsed = try UniversalCatalogScraper.invoke_parseProgramRequirementsHTML_forTests(html, baseURL: baseURL)

        XCTAssertGreaterThanOrEqual(parsed.requirements.count, 1)
        let codes = Set(
            parsed.requirements.flatMap { ($0.requiredCourses ?? []) + ($0.selectFrom ?? []) }
        )
        XCTAssertTrue(codes.contains("CSCI 212"))
        XCTAssertTrue(codes.contains("CSCI 313"))
    }

    func testParseRequirements_rutgersFixture_extractsCoreCourses() throws {
        let html = try String(
            contentsOf: TestFixturePaths.url("Coursedog/rutgers_computer_science_program.html"),
            encoding: .utf8
        )
        let baseURL = "https://catalogs.rutgers.edu/#/programs/computer-science-bs"
        let parsed = try UniversalCatalogScraper.invoke_parseProgramRequirementsHTML_forTests(html, baseURL: baseURL)

        XCTAssertFalse(parsed.requirements.isEmpty)
        let codes = Set(parsed.requirements.flatMap { $0.requiredCourses ?? [] })
        XCTAssertTrue(codes.contains("CS 111"))
    }

    func testParseCourseCodesFromRenderedText_rutgersColonCodes() {
        let html = "<html><body><p>Core: 14:440 and 01:640 required</p></body></html>"
        let codes = CoursedogRequirementsParser.parseCourseCodesFromRenderedText(html)
        XCTAssertTrue(codes.contains("14:440"))
        XCTAssertTrue(codes.contains("01:640"))
    }

    func testLiveFetch_rutgersAerospaceProgram_producesRequirements() async throws {
        try CollegeTestsSupport.skipUnlessLiveNetworkTests()
        let programURL =
            "https://newbrunswick-undergrad-25-26.catalogs.rutgers.edu/schools/eng/programs-study/aerospace"
        let parsed = try await CoursedogRequirementsParser.scrapeRequirementsWithDiagnostics(
            programURL: programURL
        )
        XCTAssertFalse(
            parsed.requirements.isEmpty,
            "Expected requirements after rendered fetch; diagnostics=\(parsed.diagnostics)"
        )
        let codes = Set(parsed.requirements.flatMap { ($0.requiredCourses ?? []) + ($0.selectFrom ?? []) })
        XCTAssertFalse(codes.isEmpty, "Expected at least one course code in requirements")
    }
}
