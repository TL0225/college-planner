// MinorProgramResolutionTests.swift
// Feature: Profile
// Purpose: Profile module — MinorProgramResolutionTests.
// Data: CollegePersistence / repositories when applicable.

import XCTest
@testable import College

@MainActor
final class MinorProgramResolutionTests: XCTestCase {
    func testCleanedProgramName_preservesMinorDisambiguator() {
        let manager = CollegePersistence.shared
        XCTAssertEqual(
            manager.cleanedProgramNameFromDisplay("Cybersecurity (Minor)"),
            "Cybersecurity (Minor)"
        )
        XCTAssertEqual(
            manager.cleanedProgramNameFromDisplay("Anthropology (BA)"),
            "Anthropology"
        )
    }

    func testCybersecurityMinor_visibleCategoriesFromFixture() throws {
        let xml = try fixtureString(named: "nyu_tandon_cybersecurity_minor.xml")
        let requirements = try CourseLeafRequirementsParser.parseRequirementsFromFixtureXML(
            xml,
            programURL: "https://bulletins.nyu.edu/undergraduate/engineering/programs/cybersecurity-minor/",
            schoolID: "new_york_university",
            programName: "Cybersecurity (Minor)"
        )

        let visible = RequirementBreakdownBuilder.visibleCategories(from: requirements)
        XCTAssertTrue(
            visible.contains(where: { $0.title.localizedCaseInsensitiveContains("Required Courses") }),
            "Required Courses must appear in breakdown categories"
        )
        let required = visible.first {
            $0.title.localizedCaseInsensitiveContains("Required Courses")
        }
        XCTAssertFalse(required?.itemCodes.isEmpty ?? true)
    }

    private func fixtureString(named filename: String) throws -> String {
        try TestFixturePaths.courseLeafString(named: filename)
    }
}
