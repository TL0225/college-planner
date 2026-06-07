// CourseLeafNYUSternBusinessBreakdownRegressionTests.swift
// Feature: Shared
// Purpose: Shared module — CourseLeafNYUSternBusinessBreakdownRegressionTests.
// Data: CollegePersistence / repositories when applicable.

import XCTest
@testable import College

/// Regression: Stern Business BS major requirements hierarchy and credit denominators.
final class CourseLeafNYUSternBusinessBreakdownRegressionTests: XCTestCase {
    func testSternBusinessBS_functionalCoreCapstoneAndConcentrationCredits() throws {
        let xml = try fixtureString(named: "nyu_stern_business_bs_major.xml")
        let requirements = try CourseLeafRequirementsParser.parseRequirementsFromFixtureXML(
            xml,
            programURL: "https://bulletins.nyu.edu/undergraduate/business/programs/business-bs/",
            schoolID: "new_york_university"
        )

        let summary = requirements
            .filter { $0.category != "__PROGRAM_TOTAL_CREDITS__" }
            .map { "\($0.displayTitle ?? "?") | sel=\($0.selectFrom?.count ?? 0) req=\($0.requiredCourses?.count ?? 0) kind=\($0.requirementKind?.rawValue ?? "?")" }
            .joined(separator: "; ")

        let allCodes = Set(requirements.flatMap { ($0.requiredCourses ?? []) + ($0.selectFrom ?? []) })
        XCTAssertTrue(allCodes.contains("MULT-UB 303"), "Capstone missing. Parsed: \(summary)")

        let capstone = requirements.first {
            ($0.requiredCourses ?? []).contains("MULT-UB 303")
        }
        XCTAssertNotNil(capstone)
        XCTAssertEqual(capstone?.parentCategory, "Major Requirements")
        XCTAssertEqual(capstone?.displayTitle, "NYC Consulting Capstone")

        let functionalCore = requirements.first {
            let codes = Set(($0.requiredCourses ?? []) + ($0.selectFrom ?? []))
            return codes.contains("ACCT-UB 4") && codes.contains("MGMT-UB 2")
                && ($0.displayTitle ?? "").localizedCaseInsensitiveContains("Functional Business Core")
        }
        guard let functionalCore else {
            return XCTFail("Expected Functional Business Core row. Parsed: \(summary)")
        }
        XCTAssertEqual(functionalCore.displayTitle, "Functional Business Core")
        XCTAssertEqual(functionalCore.parentCategory, "Major Requirements")
        XCTAssertEqual(functionalCore.selectCount, 5)
        XCTAssertEqual(
            functionalCore.creditsRequired,
            20,
            "Parser creditsRequired=\(functionalCore.creditsRequired) for \(functionalCore.category)"
        )
        XCTAssertEqual(functionalCore.requirementKind, .chooseOne)
        XCTAssertTrue(
            (functionalCore.description ?? "").localizedCaseInsensitiveContains("Select at least 5"),
            "Rule prose should live in description, not as the row title"
        )

        let misplacedRule = requirements.first {
            ($0.displayTitle ?? "").localizedCaseInsensitiveContains("Select at least 5 of the following")
        }
        XCTAssertNil(misplacedRule, "Choose rule should not be its own top-level row title")

        let concentration = requirements.first {
            ($0.displayTitle ?? "").localizedCaseInsensitiveContains("Select 12 Business Concentration credits")
                || ($0.description ?? "").localizedCaseInsensitiveContains("Select 12 Business Concentration credits")
        }
        XCTAssertNotNil(concentration)
        XCTAssertEqual(concentration?.creditsRequired, 12)
        XCTAssertTrue((concentration?.selectFrom ?? []).isEmpty)
        XCTAssertTrue((concentration?.requiredCourses ?? []).isEmpty)

        let visible = RequirementBreakdownBuilder.visibleCategories(from: requirements)
        if let concentrationVisible = visible.first(where: {
            $0.title.localizedCaseInsensitiveContains("Business Concentration")
                && $0.title.localizedCaseInsensitiveContains("Select 12")
        }) {
            XCTAssertEqual(concentrationVisible.progressTarget, 12)
        }

        if let functionalVisible = visible.first(where: { $0.title.localizedCaseInsensitiveContains("Functional Business Core") }) {
            XCTAssertEqual(functionalVisible.progressTarget, 20)
            XCTAssertEqual(functionalVisible.selectCount, 5)
        }
    }

    private func fixtureString(named filename: String) throws -> String {
        return try TestFixturePaths.courseLeafString(named: filename)
    }
}
