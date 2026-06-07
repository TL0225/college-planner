// CourseLeafRequirementsXMLTests.swift
// Feature: Shared
// Purpose: Shared module — CourseLeafRequirementsXMLTests.
// Data: CollegePersistence / repositories when applicable.

import XCTest
@testable import College

final class CourseLeafRequirementsXMLTests: XCTestCase {
    func testEndToEnd_nyuCSBA_fromFixtureIndexXML() throws {
        let xml = try fixtureString(named: "nyu_cs_ba_major.xml")
        let requirements = try CourseLeafRequirementsParser.parseRequirementsFromFixtureXML(
            xml,
            programURL: "https://bulletins.nyu.edu/undergraduate/arts-science/programs/computer-science-ba/",
            schoolID: "new_york_university"
        )
        XCTAssertFalse(requirements.isEmpty)
        XCTAssertTrue(requirements.contains(where: { ($0.requiredCourses ?? []).contains("CSCI-UA 101") }))
    }

    private func fixtureString(named filename: String) throws -> String {
        return try TestFixturePaths.courseLeafString(named: filename)
    }
}
