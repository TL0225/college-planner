// CourseLeafProgramCoverageTests.swift
// Feature: Shared
// Purpose: Shared module — CourseLeafProgramCoverageTests.
// Data: CollegePersistence / repositories when applicable.

import XCTest
@testable import College

/// Verifies CourseLeaf program parsing yields broad coverage on representative NYU bulletin pages.
final class CourseLeafProgramCoverageTests: XCTestCase {
    func testParsePrograms_nyuFixture_assignsDepartmentAndSkipsJunk() throws {
        let fixtureURL = try fixtureURL(named: "nyu_cs_ba_major.xml")
        let xml = try String(contentsOf: fixtureURL, encoding: .utf8)
        let pageURL = URL(string: "https://bulletins.nyu.edu/undergraduate/arts-science/programs/computer-science-ba/")!

        let result = CourseLeafEngine.parseCatalogPage(
            xml: xml,
            pageURL: pageURL,
            schoolID: "new_york_university"
        )

        XCTAssertEqual(result.programs.count, 1)
        let program = try XCTUnwrap(result.programs.first)
        XCTAssertEqual(program.department, "College of Arts and Science")
        XCTAssertEqual(program.college, "College of Arts and Science")
        XCTAssertEqual(program.degreeType?.uppercased(), "BA")
    }

    private func fixtureURL(named filename: String) throws -> URL {
        let bundle = Bundle(for: CourseLeafProgramCoverageTests.self)
        if let url = bundle.url(forResource: filename, withExtension: nil, subdirectory: "Fixtures/CourseLeaf") {
            return url
        }
        return try TestFixturePaths.courseLeafURL(named: filename)
    }

    func testParsePrograms_skipsProgramsListingTitle() {
        let xml = """
        <?xml version="1.0"?>
        <courseleaf>
        <title>Programs</title>
        </courseleaf>
        """
        let pageURL = URL(string: "https://bulletins.nyu.edu/undergraduate/arts-science/programs/")!
        let result = CourseLeafEngine.parseCatalogPage(
            xml: xml,
            pageURL: pageURL,
            schoolID: "new_york_university"
        )
        XCTAssertTrue(result.programs.isEmpty)
    }

    func testSitemapRepresentativeNYUUndergradProgramCount() async throws {
        throw XCTSkip("Live bulletin coverage check — run locally with network.")

        guard let baseURL = CourseLeafEngine.normalizeBaseURL("https://bulletins.nyu.edu/") else {
            XCTFail("Invalid base URL")
            return
        }
        let pageURLs = try await CourseLeafEngine.sitemapPageURLs(baseURL: baseURL)
        let undergradProgramPages = pageURLs.filter { url in
            let path = url.path.lowercased()
            return path.hasPrefix("/undergraduate/") && path.contains("/programs/")
        }

        XCTAssertGreaterThan(
            undergradProgramPages.count,
            150,
            "Expected a broad NYU undergraduate program slice in the sitemap"
        )
    }
}
