// CourseLeafRequirementsSectionTests.swift
// Feature: Shared
// Purpose: Shared module — CourseLeafRequirementsSectionTests.
// Data: CollegePersistence / repositories when applicable.

import XCTest
@testable import College

final class CourseLeafRequirementsSectionTests: XCTestCase {
    func testExtractBaseline_usesCurriculumtext_notSamplePlan() throws {
        let xml = try fixtureString(named: "nyu_cs_ba_major.xml")
        let url = URL(string: "https://bulletins.nyu.edu/undergraduate/arts-science/programs/computer-science-ba/")!
        let fragments = CourseLeafRequirementsParser.extractRequirementFragments(
            from: xml,
            schoolID: "new_york_university",
            programURL: url
        )
        XCTAssertTrue(fragments.baselineHTML.contains("sc_courselist"))
        XCTAssertFalse(fragments.baselineHTML.lowercased().contains("sc_plangrid"))
    }

    func testCMU_blacklistsSamplePlanSections() throws {
        let xml = try fixtureString(named: "cmu_undergrad_cs_major.xml")
        let url = URL(string: "http://coursecatalog.web.cmu.edu/undergraduate/computerscience/")!
        let fragments = CourseLeafRequirementsParser.extractRequirementFragments(
            from: xml,
            schoolID: "carnegie_mellon_university",
            programURL: url
        )
        XCTAssertTrue(fragments.baselineHTML.contains("15-122"))
        XCTAssertFalse(fragments.baselineHTML.contains("sc_plangrid"))
    }

    private func fixtureString(named filename: String) throws -> String {
        return try TestFixturePaths.courseLeafString(named: filename)
    }
}
