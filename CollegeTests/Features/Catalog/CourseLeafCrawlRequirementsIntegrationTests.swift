// CourseLeafCrawlRequirementsIntegrationTests.swift
// Feature: Shared
// Purpose: Shared module — CourseLeafCrawlRequirementsIntegrationTests.
// Data: CollegePersistence / repositories when applicable.

import XCTest
@testable import College

/// Verifies crawl-time requirements attachment shape (fixture `index.xml` → non-empty `DegreeRequirement`s).
final class CourseLeafCrawlRequirementsIntegrationTests: XCTestCase {
    func testParsePrograms_withRequirementsFlag_attachesRequirementsOnScrapedProgram() throws {
        let xml = try fixtureString(named: "nyu_cs_ba_major.xml")
        let pageURL = URL(string: "https://bulletins.nyu.edu/undergraduate/arts-science/programs/computer-science-ba/")!
        let programs = CourseLeafEngine.parseProgramsForTests(
            from: xml,
            pageURL: pageURL,
            schoolID: "new_york_university",
            parseRequirements: true
        )
        XCTAssertFalse(programs.isEmpty)
        let baseline = programs.first { ($0.trackVariant ?? "").isEmpty }
        XCTAssertNotNil(baseline, "Expected baseline program row")
        XCTAssertNotNil(baseline?.requirements)
        XCTAssertFalse(baseline?.requirements?.isEmpty ?? true)
    }

    private func fixtureString(named filename: String) throws -> String {
        return try TestFixturePaths.courseLeafString(named: filename)
    }
}
