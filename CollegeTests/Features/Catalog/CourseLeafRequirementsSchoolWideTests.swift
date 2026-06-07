// CourseLeafRequirementsSchoolWideTests.swift
// Feature: Shared
// Purpose: Shared module — CourseLeafRequirementsSchoolWideTests.
// Data: CollegePersistence / repositories when applicable.

import XCTest
@testable import College

final class CourseLeafRequirementsSchoolWideTests: XCTestCase {
    func testValidator_nyuCSBAFixture_passes() async {
        let xml: String
        do {
            xml = try fixtureString(named: "nyu_cs_ba_major.xml")
        } catch {
            XCTFail("Missing fixture: \(error)")
            return
        }
        let result = await CourseLeafProgramRequirementsValidator.validate(
            programURL: "https://bulletins.nyu.edu/undergraduate/arts-science/programs/computer-science-ba/",
            schoolID: "new_york_university",
            xml: xml
        )
        XCTAssertTrue(result.passed, "Expected pass, got \(result.reason?.rawValue ?? "nil")")
        XCTAssertGreaterThan(result.categoriesCount, 0)
    }

    func testValidator_fixturePrograms_meetHighPassRate() async throws {
        let fixtures: [(String, String, String)] = [
            ("nyu_cs_ba_major.xml", "https://bulletins.nyu.edu/undergraduate/arts-science/programs/computer-science-ba/", "new_york_university"),
            ("fordham_aa_major.xml", "https://bulletins.fordham.edu/undergraduate/aa-studies/programs/african-american-studies-major/", "fordham_university"),
            ("cmu_undergrad_cs_major.xml", "http://coursecatalog.web.cmu.edu/undergraduate/computerscience/", "carnegie_mellon_university")
        ]

        var programs: [ScrapedProgram] = []
        for (file, url, _) in fixtures {
            let xml = try fixtureString(named: file)
            _ = xml
            programs.append(
                ScrapedProgram(
                    name: file,
                    type: "Major",
                    url: url,
                    degreeType: "BS"
                )
            )
        }

        // Validate each fixture-backed program URL with cached XML (offline).
        var passed = 0
        var validated = 0
        for (file, url, schoolID) in fixtures {
            let xml = try fixtureString(named: file)
            let result = await CourseLeafProgramRequirementsValidator.validate(
                programURL: url,
                schoolID: schoolID,
                xml: xml
            )
            if result.reason == .allowedEmpty { continue }
            validated += 1
            if result.passed { passed += 1 }
        }
        guard validated > 0 else {
            XCTFail("No programs validated")
            return
        }
        let rate = Double(passed) / Double(validated)
        XCTAssertGreaterThanOrEqual(rate, 0.99, "Fixture program pass rate \(rate)")
    }

    private func fixtureString(named filename: String) throws -> String {
        return try TestFixturePaths.courseLeafString(named: filename)
    }
}
