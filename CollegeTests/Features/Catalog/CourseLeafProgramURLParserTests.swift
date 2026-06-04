// CourseLeafProgramURLParserTests.swift
// Feature: Shared
// Purpose: Shared module — CourseLeafProgramURLParserTests.
// Data: CollegePersistence / repositories when applicable.

import XCTest
@testable import College

final class CourseLeafProgramURLParserTests: XCTestCase {
    func testOwnership_nyuUndergraduateProgram() {
        let url = URL(string: "https://bulletins.nyu.edu/undergraduate/arts-science/programs/anthropology-ba/")!
        let ownership = CourseLeafProgramURLParser.ownership(from: url)
        XCTAssertEqual(ownership.department, "College of Arts and Science")
        XCTAssertEqual(ownership.college, "College of Arts and Science")
    }

    func testDisplayCollegeName_nyuArtsScience() {
        let url = URL(string: "https://bulletins.nyu.edu/undergraduate/arts-science/programs/computer-science-ba/")!
        XCTAssertEqual(
            CourseLeafProgramURLParser.displayCollegeName(slug: "arts-science", pageURL: url),
            "College of Arts and Science"
        )
    }

    func testDisplayCollegeName_nyuEngineeringSlug() {
        let url = URL(string: "https://bulletins.nyu.edu/undergraduate/engineering/programs/computer-science-bs/")!
        XCTAssertEqual(
            CourseLeafProgramURLParser.displayCollegeName(slug: "engineering", pageURL: url),
            "Tandon School of Engineering"
        )
    }

    func testOwnership_nyuEngineeringComputerScience() {
        let url = URL(string: "https://bulletins.nyu.edu/undergraduate/engineering/programs/computer-science-bs/")!
        let ownership = CourseLeafProgramURLParser.ownership(from: url)
        XCTAssertEqual(ownership.college, "Tandon School of Engineering")
        XCTAssertEqual(ownership.department, "Tandon School of Engineering")
    }

    func testCanonicalCollegeKey_mergesLegacyShortLabels() {
        XCTAssertEqual(
            CourseLeafProgramURLParser.canonicalCollegeKey(for: "Engineering"),
            CourseLeafProgramURLParser.canonicalCollegeKey(for: "Tandon School of Engineering")
        )
        XCTAssertEqual(
            CourseLeafProgramURLParser.canonicalCollegeKey(for: "Business"),
            CourseLeafProgramURLParser.canonicalCollegeKey(for: "Leonard N. Stern School of Business")
        )
    }

    func testOwnership_fordhamUndergraduateMajor() {
        let url = URL(string: "https://bulletin.fordham.edu/undergraduate/accounting/major/")!
        let ownership = CourseLeafProgramURLParser.ownership(from: url)
        XCTAssertEqual(ownership.department, "Accounting")
        XCTAssertEqual(ownership.college, "Undergraduate")
    }

    func testIsJunkProgramTitle_filtersListingPages() {
        XCTAssertTrue(CourseLeafProgramURLParser.isJunkProgramTitle("Programs"))
        XCTAssertTrue(CourseLeafProgramURLParser.isJunkProgramTitle("program"))
        XCTAssertFalse(CourseLeafProgramURLParser.isJunkProgramTitle("Anthropology (BA)"))
    }

    func testDegreeTypeFromTitle_extractsParentheticalToken() {
        XCTAssertEqual(CourseLeafProgramURLParser.degreeTypeFromTitle("Anthropology (BA)"), "BA")
        XCTAssertEqual(CourseLeafProgramURLParser.degreeTypeFromTitle("Social Work (BS)"), "BS")
    }
}
