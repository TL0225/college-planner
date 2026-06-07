// NYUCourseLeafRequirementsParserTests.swift
// Feature: Shared
// Purpose: Shared module — NYUCourseLeafRequirementsParserTests.
// Data: CollegePersistence / repositories when applicable.

import XCTest
@testable import College

final class NYUCourseLeafRequirementsParserTests: XCTestCase {
  func testParseNYUTandonComputerScienceBS_extractsCoreCoursesAnd128Total() throws {
    let xml = try fixtureString(named: "nyu_tandon_cs_bs_major.xml")
    let requirements = try CourseLeafRequirementsParser.parseRequirementsFromFixtureXML(
      xml,
      programURL: "https://bulletins.nyu.edu/undergraduate/engineering/programs/computer-science-bs/",
      schoolID: "new_york_university"
    )

    let categories = Set(requirements.map(\.category))
    XCTAssertTrue(
      categories.contains(where: { $0.localizedCaseInsensitiveContains("Computer Science") }),
      "Expected a Computer Science requirements section"
    )

    let allCodes = Set(
      requirements.flatMap { req in
        (req.requiredCourses ?? []) + (req.selectFrom ?? [])
      }
    )
    XCTAssertTrue(allCodes.contains("CS-UY 1114"), "Expected Tandon CS core course CS-UY 1114")
    XCTAssertTrue(allCodes.contains("MA-UY 1024"), "Expected Tandon math course MA-UY 1024")

    let footerTotal = requirements.first {
      $0.category == "__PROGRAM_TOTAL_CREDITS__"
    }?.creditsRequired
    XCTAssertEqual(footerTotal, 128, "NYU BS program table should declare 128 total credits")
  }

  func testParseNYUAbuDhabiComputerScienceBS_respectsSectionHeadersAndSkipsReferenceTable() throws {
    let xml = try fixtureString(named: "nyu_abu_dhabi_cs_bs_major.xml")
    let requirements = try CourseLeafRequirementsParser.parseRequirementsFromFixtureXML(
      xml,
      programURL: "https://bulletins.nyu.edu/undergraduate/abu-dhabi/programs/computer-science-bs/",
      schoolID: "new_york_university"
    )

    let categories = Set(requirements.map(\.category))
    XCTAssertTrue(
      categories.contains("General Education Requirements")
        || requirements.contains(where: {
          $0.parentCategory?.localizedCaseInsensitiveContains("General Education Requirements") == true
        }),
      "Expected General Education Requirements; got: \(categories.sorted())"
    )
    XCTAssertTrue(
      categories.contains("Major Required Courses")
        || requirements.contains(where: { $0.category.localizedCaseInsensitiveContains("Major Required Courses") }),
      "Expected Major Required Courses; got: \(categories.sorted())"
    )
    XCTAssertTrue(
      categories.contains("Capstone")
        || requirements.contains(where: { $0.category.localizedCaseInsensitiveContains("Capstone") }),
      "Expected Capstone; got: \(categories.sorted())"
    )

    let allCodes = Set(
      requirements.flatMap { req in
        (req.requiredCourses ?? []) + (req.selectFrom ?? [])
      }
    )
    XCTAssertTrue(allCodes.contains("CS-UH 1001"))
    XCTAssertTrue(allCodes.contains("CS-UH 1050"))
    XCTAssertTrue(allCodes.contains("MATH-UH 1012Q"))
    XCTAssertFalse(allCodes.contains("UH 1001"))
    XCTAssertFalse(allCodes.contains("UH 1050"))

    let majorElectives = requirements.first {
      ($0.category.localizedCaseInsensitiveContains("Major Electives")
        || $0.parentCategory?.localizedCaseInsensitiveContains("Major Electives") == true)
        && ($0.selectCount ?? 0) > 0
    }
    XCTAssertNotNil(majorElectives, "Expected Major Electives rule/choose row with selectCount")
    XCTAssertEqual(majorElectives?.selectCount, 2)
    XCTAssertTrue((majorElectives?.selectFrom ?? []).isEmpty)
    XCTAssertTrue((majorElectives?.requiredCourses ?? []).isEmpty)

    let genEdRows = requirements.filter {
      $0.category.localizedCaseInsensitiveContains("General Education Requirements")
        || $0.parentCategory?.localizedCaseInsensitiveContains("General Education Requirements") == true
    }
    XCTAssertFalse(genEdRows.isEmpty, "Expected at least one General Education row")
    let genEdText = genEdRows.map {
      [$0.description, $0.displayTitle, $0.category, $0.parentCategory]
        .compactMap { $0 }
        .joined(separator: " ")
    }.joined(separator: "\n")
    XCTAssertTrue(
      genEdText.localizedCaseInsensitiveContains("Physical Education"),
      "Expected Physical Education in Gen Ed rows; got: \(genEdText)"
    )
    XCTAssertTrue(genEdRows.allSatisfy { ($0.requiredCourses ?? []).isEmpty })

    let footerTotal = requirements.first {
      $0.category == "__PROGRAM_TOTAL_CREDITS__"
    }?.creditsRequired
    XCTAssertEqual(footerTotal, 128)
  }

  func testParseCourseLeaf_doesNotSplitHyphenatedCampusCourseCodes() throws {
    let html = """
    <html><body>
    <table class="sc_courselist"><tbody>
    <tr class="areaheader"><td colspan="2"><span class="courselistcomment areaheader">Major Required Courses</span></td><td class="hourscol"></td></tr>
    <tr><td class="codecol"><a href="#" title="CS-UH 1002" class="bubblelink code" onclick="return showCourse(this, 'CS-UH 1002');">CS-UH 1002</a></td><td>Discrete Mathematics</td><td class="hourscol">4</td></tr>
    </tbody></table>
    </body></html>
    """

    let parsed = try UniversalCatalogScraper.invoke_parseProgramRequirementsHTML_forTests(
      html,
      baseURL: "https://bulletins.nyu.edu/undergraduate/abu-dhabi/programs/computer-science-bs/"
    )

    let codes = Set(parsed.requirements.flatMap { $0.requiredCourses ?? [] })
    XCTAssertEqual(codes, ["CS-UH 1002"])
  }

  func testParseNYUCASComputerScienceBA_fixture() throws {
    let xml = try fixtureString(named: "nyu_cs_ba_major.xml")
    let requirements = try CourseLeafRequirementsParser.parseRequirementsFromFixtureXML(
      xml,
      programURL: "https://bulletins.nyu.edu/undergraduate/arts-science/programs/computer-science-ba/",
      schoolID: "new_york_university"
    )

    let codes = Set(requirements.flatMap { $0.requiredCourses ?? [] })
    XCTAssertTrue(codes.contains("CSCI-UA 101"))
    XCTAssertEqual(
      requirements.first { $0.category == "__PROGRAM_TOTAL_CREDITS__" }?.creditsRequired,
      128
    )
  }

  private func fixtureString(named filename: String) throws -> String {
    let url = try fixtureURL(named: filename)
    return try String(contentsOf: url, encoding: .utf8)
  }

  private func fixtureURL(named filename: String) throws -> URL {
    let bundle = Bundle(for: NYUCourseLeafRequirementsParserTests.self)
    if let url = bundle.url(forResource: filename, withExtension: nil, subdirectory: "Fixtures/CourseLeaf") {
      return url
    }
    return try TestFixturePaths.courseLeafURL(named: filename)
  }
}
