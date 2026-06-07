// CourseLeafNYUCSBABreakdownRegressionTests.swift
// Feature: Shared
// Purpose: Shared module — CourseLeafNYUCSBABreakdownRegressionTests.
// Data: CollegePersistence / repositories when applicable.

import XCTest
@testable import College

/// Regression: NYU CAS CS BA baseline curriculum must include Gen Ed + major blocks (not honors-only subset).
final class CourseLeafNYUCSBABreakdownRegressionTests: XCTestCase {
    func testNYUCSBA_baselineIncludesGenEdAndMajorNotHonorsTrack() throws {
        let xml = try fixtureString(named: "nyu_cs_ba_major.xml")
        let requirements = try CourseLeafRequirementsParser.parseRequirementsFromFixtureXML(
            xml,
            programURL: "https://bulletins.nyu.edu/undergraduate/arts-science/programs/computer-science-ba/",
            schoolID: "new_york_university"
        )

        let categories = Set(requirements.map(\.category))
        XCTAssertTrue(
            categories.contains(where: { $0.localizedCaseInsensitiveContains("General Education") }),
            "Expected General Education category; got: \(categories.sorted())"
        )

        let allCodes = Set(requirements.flatMap { ($0.requiredCourses ?? []) + ($0.selectFrom ?? []) })
        XCTAssertTrue(allCodes.contains("CSCI-UA 101"))
        XCTAssertTrue(allCodes.contains("EXPOS-UA 1"))
        XCTAssertFalse(allCodes.contains("CSCI-UA 421"), "Honors-only course should not appear in baseline curriculum")

        let visible = RequirementBreakdownBuilder.visibleCategories(from: requirements)
        let titles = visible.map(\.title).joined(separator: " | ")
        XCTAssertTrue(
            titles.localizedCaseInsensitiveContains("General Education"),
            "Breakdown should show Gen Ed prose/credits; visible: \(titles)"
        )

        let totalFooter = requirements.first { $0.category == "__PROGRAM_TOTAL_CREDITS__" }?.creditsRequired
        XCTAssertEqual(totalFooter, 128)

        XCTAssertTrue(
            categories.contains(where: { $0.localizedCaseInsensitiveContains("Foreign Language") }),
            "Expected Foreign Language bucket; got: \(categories.sorted())"
        )
        XCTAssertTrue(
            categories.contains(where: { $0.localizedCaseInsensitiveContains("Physical Science") }),
            "Expected Physical Science bucket"
        )

        let firstYearSeminar = requirements.first {
            $0.category.localizedCaseInsensitiveContains("First-Year Seminar")
                && ($0.requiredCourses ?? []).contains("EXPOS-UA 1")
        }
        XCTAssertNotNil(firstYearSeminar, "Expected First-Year Seminar row with EXPOS-UA 1")
        XCTAssertEqual(firstYearSeminar?.creditsRequired, 4)
        XCTAssertEqual(firstYearSeminar?.displayTitle, "First-Year Seminar")
        XCTAssertEqual(firstYearSeminar?.parentCategory, "General Education Requirements")

        let foreignLanguage = requirements.first {
            $0.displayTitle?.localizedCaseInsensitiveContains("Foreign Language") == true
                || ($0.category.localizedCaseInsensitiveContains("Foreign Language")
                    && !$0.category.localizedCaseInsensitiveContains("First-Year"))
        }
        XCTAssertNotNil(foreignLanguage)
        XCTAssertEqual(foreignLanguage?.parentCategory, "General Education Requirements")
        XCTAssertFalse(
            foreignLanguage?.category.localizedCaseInsensitiveContains("First-Year Seminar") ?? true,
            "Foreign Language must not inherit First-Year Seminar subsection path"
        )

        let mathRequired = requirements.first {
            $0.category.localizedCaseInsensitiveContains("Mathematics")
                && ($0.requiredCourses ?? []).contains("MATH-UA 120")
        }
        XCTAssertNotNil(mathRequired, "Expected Mathematics Courses row with MATH-UA 120")
        XCTAssertFalse((mathRequired?.selectFrom ?? []).contains("MATH-UA 121"))

        let mathChooseOne = requirements.first {
            $0.category.localizedCaseInsensitiveContains("Select one of the following")
                && ($0.selectFrom ?? []).contains("MATH-UA 121")
        }
        XCTAssertNotNil(mathChooseOne)
        XCTAssertEqual(mathChooseOne?.selectCount, 1)
        XCTAssertEqual(mathChooseOne?.creditsRequired, 4)

        let electiveRows = requirements.filter {
            $0.category.localizedCaseInsensitiveContains("Electives")
                || $0.parentCategory?.localizedCaseInsensitiveContains("Electives") == true
        }
        let electiveCredits = Set(electiveRows.filter { $0.creditsRequired == 20 || $0.creditsRequired == 28 }.map(\.creditsRequired))
        XCTAssertTrue(electiveCredits.contains(20), "Expected 20cr CSCI 4XX rule row")
        XCTAssertTrue(electiveCredits.contains(28), "Expected 28cr Other Elective Credits row")
    }

    private func fixtureString(named filename: String) throws -> String {
        return try TestFixturePaths.courseLeafString(named: filename)
    }
}
