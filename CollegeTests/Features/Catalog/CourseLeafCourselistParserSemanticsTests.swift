// CourseLeafCourselistParserSemanticsTests.swift
// Feature: Shared
// Purpose: Shared module — CourseLeafCourselistParserSemanticsTests.
// Data: CollegePersistence / repositories when applicable.

import XCTest
@testable import College

final class CourseLeafCourselistParserSemanticsTests: XCTestCase {
    func testParse_selectTwoFromFollowing_emptyList() throws {
        let html = """
        <html><body>
        <table class="sc_courselist"><tbody>
        <tr class="areaheader"><td colspan="2"><span class="courselistcomment areaheader">Major Electives</span></td><td class="hourscol"></td></tr>
        <tr><td colspan="2"><span class="courselistcomment">Select two courses from the following:</span></td><td class="hourscol">8</td></tr>
        </tbody></table>
        </body></html>
        """
        let parsed = try UniversalCatalogScraper.invoke_parseProgramRequirementsHTML_forTests(
            html,
            baseURL: "https://example.edu/programs/test/"
        ).requirements
        let elective = parsed.first { $0.category.localizedCaseInsensitiveContains("Major Electives") }
        XCTAssertNotNil(elective)
        XCTAssertEqual(elective?.selectCount, 2)
    }

    func testParse_hyphenatedCampusCode() throws {
        let html = """
        <html><body>
        <table class="sc_courselist"><tbody>
        <tr class="areaheader"><td colspan="2"><span class="courselistcomment areaheader">Major Required Courses</span></td><td class="hourscol"></td></tr>
        <tr><td class="codecol"><span class="code_bubble" data-code-bubble="CS-UH 1002">CS-UH 1002</span></td><td>Discrete Mathematics</td><td class="hourscol">4</td></tr>
        </tbody></table>
        </body></html>
        """
        let parsed = try UniversalCatalogScraper.invoke_parseProgramRequirementsHTML_forTests(
            html,
            baseURL: "https://bulletins.nyu.edu/undergraduate/abu-dhabi/programs/computer-science-bs/"
        ).requirements
        let codes = Set(parsed.flatMap { $0.requiredCourses ?? [] })
        XCTAssertEqual(codes, ["CS-UH 1002"])
    }

    func testParse_areaheaderAndSubheaderCredits() throws {
        let html = """
        <html><body>
        <table class="sc_courselist"><tbody>
        <tr class="areaheader"><td colspan="2"><span class="courselistcomment areaheader">Core</span></td><td class="hourscol"></td></tr>
        <tr class="areasubheader"><td colspan="2"><span class="courselistcomment areasubheader">Core Competencies</span></td><td class="hourscol"></td></tr>
        <tr><td colspan="2"><span class="courselistcomment">Writing</span></td><td class="hourscol">4</td></tr>
        <tr><td colspan="2"><span class="courselistcomment">Quantitative Reasoning</span></td><td class="hourscol">4</td></tr>
        </tbody></table>
        </body></html>
        """
        let parsed = try UniversalCatalogScraper.invoke_parseProgramRequirementsHTML_forTests(
            html,
            baseURL: "https://example.edu/"
        ).requirements
        let visible = RequirementBreakdownBuilder.visibleCategories(from: parsed)
        XCTAssertTrue(visible.contains(where: { $0.title.contains("Core Competencies") }))
    }
}
