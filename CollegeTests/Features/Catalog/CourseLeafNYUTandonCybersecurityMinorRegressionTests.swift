// CourseLeafNYUTandonCybersecurityMinorRegressionTests.swift
// Feature: Shared
// Purpose: Shared module — CourseLeafNYUTandonCybersecurityMinorRegressionTests.
// Data: CollegePersistence / repositories when applicable.

import XCTest
@testable import College

final class CourseLeafNYUTandonCybersecurityMinorRegressionTests: XCTestCase {
    func testCybersecurityMinor_includesRequiredAndElectiveSections() throws {
        let xml = try fixtureString(named: "nyu_tandon_cybersecurity_minor.xml")
        let requirements = try CourseLeafRequirementsParser.parseRequirementsFromFixtureXML(
            xml,
            programURL: "https://bulletins.nyu.edu/undergraduate/engineering/programs/cybersecurity-minor/",
            schoolID: "new_york_university",
            programName: "Cybersecurity (Minor)"
        )

        let summary = requirements
            .filter { $0.category != "__PROGRAM_TOTAL_CREDITS__" }
            .map { "\($0.displayTitle ?? "?") | req=\($0.requiredCourses?.count ?? 0) sel=\($0.selectFrom?.count ?? 0) kind=\($0.requirementKind?.rawValue ?? "?")" }
            .joined(separator: "; ")

        let required = requirements.first {
            ($0.displayTitle ?? "").localizedCaseInsensitiveContains("Required Courses")
                || $0.category.localizedCaseInsensitiveContains("Required Courses")
        }
        XCTAssertNotNil(required, "Expected Required Courses row. Parsed: \(summary)")

        let requiredCodes = Set(required?.requiredCourses ?? [])
        XCTAssertTrue(requiredCodes.contains("CS-UY 3923"))
        XCTAssertTrue(requiredCodes.contains("CS-UY 3933"))
        XCTAssertTrue(requiredCodes.contains("CS-UY 4753"))
        XCTAssertTrue(requiredCodes.contains("CS-UY 4793"))
        XCTAssertTrue(requiredCodes.contains("ECE-UY 3613"))

        let requiredDetailed = required?.requiredCoursesDetailed ?? []
        let networking = requiredDetailed.filter {
            $0.code == "CS-UY 4793" || $0.code == "ECE-UY 3613"
        }
        XCTAssertEqual(networking.count, 2)
        let orKeys = Set(networking.compactMap(\.alternativeGroupKey))
        XCTAssertEqual(orKeys.count, 1, "OR alternatives should share one group key")

        let elective = requirements.first {
            ($0.selectFrom ?? []).contains("CS-UY 4773")
        }
        XCTAssertNotNil(elective, "Expected elective choose-one row. Parsed: \(summary)")
        XCTAssertEqual(elective?.selectCount, 1)
        XCTAssertEqual(elective?.creditsRequired, 3)

        let visible = RequirementBreakdownBuilder.visibleCategories(from: requirements)
        XCTAssertTrue(
            visible.contains(where: { $0.title.localizedCaseInsensitiveContains("Required Courses") }),
            "Breakdown should surface Required Courses"
        )
    }

    func testCybersecurityMinor_requiredCoursesSurviveProseBeforeNextAreaHeader() throws {
        var xml = try fixtureString(named: "nyu_tandon_cybersecurity_minor.xml")
        let strayProse = """
        <tr class="odd"><td colspan="2"><span class="courselistcomment">Complete one of the following options</span></td><td class="hourscol"></td></tr>
        """
        xml = xml.replacingOccurrences(
            of: "<tr class=\"odd areaheader \"><td colspan=\"2\"><span class=\"courselistcomment areaheader \">Elective Course</span>",
            with: strayProse + "<tr class=\"odd areaheader \"><td colspan=\"2\"><span class=\"courselistcomment areaheader \">Elective Course</span>"
        )

        let requirements = try CourseLeafRequirementsParser.parseRequirementsFromFixtureXML(
            xml,
            programURL: "https://bulletins.nyu.edu/undergraduate/engineering/programs/cybersecurity-minor/",
            schoolID: "new_york_university",
            programName: "Cybersecurity (Minor)"
        )

        let required = requirements.first {
            ($0.displayTitle ?? "").localizedCaseInsensitiveContains("Required Courses")
                || $0.category.localizedCaseInsensitiveContains("Required Courses")
        }
        XCTAssertNotNil(required, "Required Courses must not be dropped when prose precedes the next area header")
        XCTAssertTrue((required?.requiredCourses ?? []).contains("CS-UY 3923"))
    }

    private func fixtureString(named filename: String) throws -> String {
        return try TestFixturePaths.courseLeafString(named: filename)
    }
}
