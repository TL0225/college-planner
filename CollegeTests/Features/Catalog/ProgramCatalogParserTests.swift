// ProgramCatalogParserTests.swift
// Feature: Shared
// Purpose: Shared module — ProgramCatalogParserTests.
// Data: CollegePersistence / repositories when applicable.

import XCTest
@testable import College

final class ProgramCatalogParserTests: XCTestCase {
    func testParseProgramCatalogRequirementSheet_extractsCoreGroupsAndGraduationCredits() {
        let html = """
        <div id="acalog-content">
          <h1>AI and Geospatial Analytics BS</h1>
          <h3>Math Core (12 credits)</h3>
          <ul>
            <li>MTH 114LEC - Precalculus Credits: 4</li>
            <li>MTH 141LR - College Calculus I Credits: 4</li>
          </ul>
          <h3>AI &amp; Society Core (15 credits)</h3>
          <p>Choose two of the following AI &amp; Society Electives:</p>
          <ul>
            <li>AI 101LEC - AI &amp; Society Credits: 3</li>
            <li>AI 111LEC - AI &amp; Ethics Credits: 3</li>
          </ul>
          <h3>Total Credits Required for Graduation: 120</h3>
        </div>
        """
        let sheet = ModernCampusEngine.invoke_parseProgramCatalogRequirementSheetFromHTML_forTests(html)
        XCTAssertEqual(sheet.programName, "AI and Geospatial Analytics BS")
        XCTAssertEqual(sheet.totalCreditsRequired, 120)
        XCTAssertGreaterThanOrEqual(sheet.requirementGroups.count, 2)
        let math = sheet.requirementGroups.first { $0.groupName.contains("Math Core") }
        XCTAssertNotNil(math)
        XCTAssertTrue(math?.courseOptions.contains(where: { $0.contains("MTH") }) ?? false)
        let soc = sheet.requirementGroups.first { $0.groupName.contains("Society Core") }
        XCTAssertEqual(soc?.chooseCount, 2)
    }

    func testParseProgramHTML_extractsPreviewProgramHyperlinks() {
        let html = """
        <div id="acalog-content">
          <h3>Graduate Programs</h3>
          <a href="preview_program.php?catoid=21&amp;poid=1849">Computer Science, M.S.</a>
          <a href="preview_program.php?catoid=21&amp;poid=999">Cyber Defense, Ph.D.</a>
        </div>
        """
        let programs = ModernCampusEngine.invoke_parseProgramHTML_forTests(
            html,
            baseURL: "https://catalog.dsu.edu"
        )
        XCTAssertEqual(programs.count, 2)
        let ms = programs.first { $0.name.contains("Computer Science") }
        XCTAssertNotNil(ms)
        XCTAssertTrue(ms?.url.contains("preview_program.php") == true)
        XCTAssertTrue(ms?.url.contains("poid=1849") == true)
        XCTAssertTrue(ms?.url.contains("catoid=21") == true)
    }

    func testParseProgramCatalogRequirementSheet_extractsCoidFromPreviewCourseHref() {
        let html = """
        <div id="acalog-content">
          <h1>Business MIS BS</h1>
          <h3>Core (6 credits)</h3>
          <ul>
            <li><a href="preview_course_nopop.php?catoid=7&amp;coid=19581">MIS 311</a> - Systems Analysis</li>
          </ul>
        </div>
        """
        let sheet = ModernCampusEngine.invoke_parseProgramCatalogRequirementSheetFromHTML_forTests(html)
        XCTAssertEqual(sheet.courseCoidMap["MIS 311"], "19581")
    }

    func testExpandedDegreeRequirements_mapsGroupKinds() {
        let sheet = ProgramCatalogRequirementSheet(
            programName: "Sample BS",
            totalCreditsRequired: 120,
            requirementGroups: [
                .init(groupName: "Math Core", courseOptions: ["MTH 141", "MTH 142"], chooseCount: nil),
                .init(groupName: "Electives", courseOptions: ["AI 101", "AI 111"], chooseCount: 2),
                .init(groupName: "Choose two 700-level courses", courseOptions: [], chooseCount: 2),
            ]
        )
        let expanded = sheet.expandedDegreeRequirements()
        let math = expanded.first { $0.category.localizedCaseInsensitiveContains("Math Core") }
        XCTAssertEqual(math?.requirementKind, .courseList)

        let chooseListed = expanded.first { $0.category.localizedCaseInsensitiveContains("Electives") }
        XCTAssertEqual(chooseListed?.requirementKind, .chooseOne)
        XCTAssertEqual(chooseListed?.selectCount, 2)

        let rule = expanded.first { $0.category.localizedCaseInsensitiveContains("700-level") }
        XCTAssertEqual(rule?.requirementKind, .ruleBucket)
        XCTAssertEqual(rule?.selectCount, 2)

        XCTAssertEqual(
            expanded.first { $0.category == "__PROGRAM_TOTAL_CREDITS__" }?.creditsRequired,
            120
        )
    }
}
