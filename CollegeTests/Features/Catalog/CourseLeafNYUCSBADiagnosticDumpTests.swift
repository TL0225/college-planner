// CourseLeafNYUCSBADiagnosticDumpTests.swift
// Feature: Shared
// Purpose: Shared module — CourseLeafNYUCSBADiagnosticDumpTests.
// Data: CollegePersistence / repositories when applicable.

import XCTest
@testable import College

/// Prints parse + breakdown shape for NYU CAS CS BA (debug aid).
final class CourseLeafNYUCSBADiagnosticDumpTests: XCTestCase {
    func testDumpNYUCSBA_categoriesAndVisibleBreakdown() throws {
        let xml = try fixtureString(named: "nyu_cs_ba_major.xml")
        let url = "https://bulletins.nyu.edu/undergraduate/arts-science/programs/computer-science-ba/"
        let requirements = try CourseLeafRequirementsParser.parseRequirementsFromFixtureXML(
            xml,
            programURL: url,
            schoolID: "new_york_university",
            programName: "Computer Science (BA)"
        )

        let categories = requirements
            .filter { $0.category != "__PROGRAM_TOTAL_CREDITS__" }
            .map { req -> String in
                let codes = (req.requiredCourses ?? []).count + (req.selectFrom ?? []).count
                return "\(req.category) | cr=\(req.creditsRequired) | codes=\(codes) | desc=\((req.description ?? "").prefix(40))"
            }

        let visible = RequirementBreakdownBuilder.visibleCategories(from: requirements)
        let visibleSummary = visible.map { "\($0.title) target=\($0.progressTarget) codes=\($0.itemCodes.count)" }

        // Test always passes; inspect console when diagnosing rescrape issues.
        print("=== NYU CS BA parsed categories (\(categories.count)) ===")
        categories.forEach { print($0) }
        print("=== Visible breakdown (\(visible.count)) ===")
        visibleSummary.forEach { print($0) }

        XCTAssertTrue(categories.contains(where: { $0.localizedCaseInsensitiveContains("General Education") }))
        XCTAssertGreaterThanOrEqual(visible.count, 4)
    }

    func testCrawlShape_baselineVsHonorsPrograms() throws {
        let xml = try fixtureString(named: "nyu_cs_ba_major.xml")
        let pageURL = URL(string: "https://bulletins.nyu.edu/undergraduate/arts-science/programs/computer-science-ba/")!
        let programs = CourseLeafEngine.parseProgramsForTests(
            from: xml,
            pageURL: pageURL,
            schoolID: "new_york_university",
            parseRequirements: true
        )
        for p in programs {
            let codeCount = (p.requirements ?? []).flatMap { ($0.requiredCourses ?? []) + ($0.selectFrom ?? []) }.count
            print("PROGRAM: \(p.name) url=\(p.url) track=\(p.trackVariant ?? "baseline") reqRows=\(p.requirements?.count ?? 0) codes=\(codeCount)")
        }
        let baseline = programs.first { ($0.trackVariant ?? "").isEmpty }
        XCTAssertNotNil(baseline)
        let honors = programs.first { $0.trackVariant == "honors" }
        XCTAssertNotNil(honors)
        let baselineCodes = Set((baseline?.requirements ?? []).flatMap { ($0.requiredCourses ?? []) + ($0.selectFrom ?? []) })
        XCTAssertTrue(baselineCodes.contains("EXPOS-UA 1"))
        XCTAssertFalse(baselineCodes.contains("CSCI-UA 421"))
        let honorsCodes = Set((honors?.requirements ?? []).flatMap { ($0.requiredCourses ?? []) + ($0.selectFrom ?? []) })
        XCTAssertTrue(honorsCodes.contains("CSCI-UA 421"))
    }

    private func fixtureString(named filename: String) throws -> String {
        return try TestFixturePaths.courseLeafString(named: filename)
    }
}
