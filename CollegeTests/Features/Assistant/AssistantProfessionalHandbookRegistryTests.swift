// AssistantProfessionalHandbookRegistryTests.swift
// Feature: Assistant
// Purpose: Assistant module — AssistantProfessionalHandbookRegistryTests.
// Data: CollegePersistence / repositories when applicable.

import XCTest
@testable import College

final class AssistantProfessionalHandbookRegistryTests: XCTestCase {

    func testLawMatchesJDTokenNotBareLawWordInUnrelatedText() {
        XCTAssertNotNil(
            AssistantProfessionalHandbookRegistry.entry(
                collegeName: "Arts and Sciences",
                resolvedCollegeFromMajor: nil,
                major: "JD expected",
                minor: nil,
                majorEntityName: nil,
                degreeType: nil
            )
        )
        XCTAssertNil(
            AssistantProfessionalHandbookRegistry.entry(
                collegeName: "Arts and Sciences",
                resolvedCollegeFromMajor: nil,
                major: "business law seminar elective",
                minor: nil,
                majorEntityName: nil,
                degreeType: nil
            )
        )
    }

    func testLawSchoolSecondarySignalFromCollegeString() {
        let e = AssistantProfessionalHandbookRegistry.entry(
            collegeName: "School of Law",
            resolvedCollegeFromMajor: nil,
            major: nil,
            minor: nil,
            majorEntityName: nil,
            degreeType: nil
        )
        XCTAssertNotNil(e)
        XCTAssertTrue(e?.url.contains("law.buffalo.edu") == true)
    }

    func testPlannerBlockIncludesDisclaimerLine() {
        let block = AssistantProfessionalHandbookRegistry.plannerBlock(
            collegeName: "School of Law",
            resolvedCollegeFromMajor: nil,
            major: nil,
            minor: nil,
            majorEntityName: nil,
            degreeType: nil
        )
        XCTAssertNotNil(block)
        XCTAssertTrue(block?.localizedCaseInsensitiveContains("not legal advice") == true)
    }
}
