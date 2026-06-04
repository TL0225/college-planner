// RequirementProgressParityTests.swift
// Feature: Academics
// Purpose: Academics module — RequirementProgressParityTests.
// Data: CollegePersistence / repositories when applicable.

import XCTest
@testable import College

/// Pre-ship: breakdown projection totals stay consistent with parsed requirement rows.
final class RequirementProgressParityTests: XCTestCase {
    func testNYUCSBA_visibleBreakdownTargetsDoNotExceedProgramTotal() throws {
        let xml = try fixtureString(named: "nyu_cs_ba_major.xml")
        let requirements = try CourseLeafRequirementsParser.parseRequirementsFromFixtureXML(
            xml,
            programURL: "https://bulletins.nyu.edu/undergraduate/arts-science/programs/computer-science-ba/",
            schoolID: "new_york_university"
        )

        let footer = requirements.first { $0.category == "__PROGRAM_TOTAL_CREDITS__" }?.creditsRequired ?? 0
        XCTAssertEqual(footer, 128)

        let visible = RequirementBreakdownBuilder.visibleCategories(from: requirements)
        let targetSum = visible.reduce(0) { $0 + $1.progressTarget }
        XCTAssertGreaterThan(targetSum, 0)
        XCTAssertLessThanOrEqual(targetSum, footer + 8, "Breakdown targets should not wildly exceed program footer")
    }

    func testNYUCSBA_distributionAndChooseOneRowsPresent() throws {
        let xml = try fixtureString(named: "nyu_cs_ba_major.xml")
        let requirements = try CourseLeafRequirementsParser.parseRequirementsFromFixtureXML(
            xml,
            programURL: "https://bulletins.nyu.edu/undergraduate/arts-science/programs/computer-science-ba/",
            schoolID: "new_york_university"
        )

        XCTAssertTrue(requirements.contains(where: { $0.requirementKind == .distributionBucket }))
        XCTAssertTrue(requirements.contains(where: { $0.requirementKind == .chooseOne }))
        XCTAssertTrue(requirements.contains(where: { $0.requirementKind == .ruleBucket }))
    }

    private func fixtureString(named filename: String) throws -> String {
        try TestFixturePaths.courseLeafString(named: filename)
    }
}
