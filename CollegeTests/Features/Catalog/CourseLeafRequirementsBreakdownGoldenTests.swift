// CourseLeafRequirementsBreakdownGoldenTests.swift
// Feature: Shared
// Purpose: Shared module — CourseLeafRequirementsBreakdownGoldenTests.
// Data: CollegePersistence / repositories when applicable.

import XCTest
@testable import College

final class CourseLeafRequirementsBreakdownGoldenTests: XCTestCase {
    func testBreakdown_nyuCSBA_hasVisibleCategoriesWithCredits() throws {
        let xml = try fixtureString(named: "nyu_cs_ba_major.xml")
        let requirements = try CourseLeafRequirementsParser.parseRequirementsFromFixtureXML(
            xml,
            programURL: "https://bulletins.nyu.edu/undergraduate/arts-science/programs/computer-science-ba/",
            schoolID: "new_york_university"
        )
        let visible = RequirementBreakdownBuilder.visibleCategories(from: requirements)
        XCTAssertFalse(visible.isEmpty)
        XCTAssertTrue(visible.contains(where: { $0.progressTarget > 0 || !$0.itemCodes.isEmpty }))
    }

    private func fixtureString(named filename: String) throws -> String {
        return try TestFixturePaths.courseLeafString(named: filename)
    }
}
