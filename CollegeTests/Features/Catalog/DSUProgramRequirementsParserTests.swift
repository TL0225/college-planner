// DSUProgramRequirementsParserTests.swift
// Feature: Shared
// Purpose: Shared module — DSUProgramRequirementsParserTests.
// Data: CollegePersistence / repositories when applicable.

import XCTest
@testable import College

/// DSU Modern Campus program pages use h2 category blocks under an h3 "Program Requirements" region.
final class DSUProgramRequirementsParserTests: XCTestCase {
    private let dsuCyberDefenseSnippet = """
    <div id="acalog-content">
      <h3><strong>Program Requirements</strong></h3>
      <div class="custom_leftpad_20">
        <div class="acalog-core">
          <h2>Required Core (30 Credits)</h2>
          <ul>
            <li class="acalog-course"><span><a href="#" onClick="showCourse('45', '28418',this); return false;">INFA 702 - Introduction to Data Privacy</a> 3 credits</span></li>
            <li class="acalog-course"><span><a href="#" onClick="showCourse('45', '28294',this); return false;">INFA 713 - Managing Security Risks</a> 3 credits</span></li>
            <li class="acalog-course"><span><a href="#" onClick="showCourse('45', '28390',this); return false;">INFA 735 - Offensive Security</a> 3 credits</span></li>
            <li class="acalog-course"><span><a href="#" onClick="showCourse('45', '28399',this); return false;">INFA 754 - Network Security Monitoring and Intrusion Detection</a> 3 credits</span></li>
          </ul>
        </div>
        <div class="acalog-core">
          <h3>Security Management and Compliance Specialization</h3>
          <ul>
            <li class="acalog-course"><span><a href="#" onClick="showCourse('45', '28389',this); return false;">INFA 720 - Incident Response</a> 3 credits</span></li>
            <li class="acalog-adhoc-list-item acalog-adhoc-after">Choose two 700-800 level courses from INFA, CSC, INFS or BADM prefix (except INFA 701) 6 credits</li>
          </ul>
        </div>
      </div>
      <div class="acalog-core"><h2>Assessment/Evaluation Activities</h2><p>Done.</p></div>
    </div>
    """

    func testParseProgramRequirements_includesRequiredCoreAndElectiveChoiceRule() throws {
        let parsed = try UniversalCatalogScraper.invoke_parseProgramRequirementsHTML_forTests(
            dsuCyberDefenseSnippet,
            baseURL: "https://catalog.dsu.edu/preview_program.php?catoid=45&poid=3975"
        )
        let categories = Set(parsed.requirements.map(\.category))
        XCTAssertTrue(categories.contains(where: { $0.localizedCaseInsensitiveContains("Required Core") }))

        let core = parsed.requirements.first { $0.category.localizedCaseInsensitiveContains("Required Core") }
        XCTAssertNotNil(core)
        let coreCodes = Set(core?.requiredCourses ?? [])
        XCTAssertTrue(coreCodes.contains("INFA 702"))
        XCTAssertTrue(coreCodes.contains("INFA 754"))

        let electiveRule = parsed.requirements.first {
            $0.category.localizedCaseInsensitiveContains("Choose two 700-800")
        }
        XCTAssertNotNil(electiveRule)
        XCTAssertEqual(electiveRule?.selectCount, 2)
        XCTAssertGreaterThanOrEqual(electiveRule?.creditsRequired ?? 0, 6)
        XCTAssertEqual(electiveRule?.requirementKind, .ruleBucket)

        let coreKind = core?.requirementKind
        XCTAssertTrue(coreKind == .courseList || coreKind == nil)
    }

    func testParseProgramRequirements_electiveRuleKindIsRuleBucket() throws {
        let parsed = try UniversalCatalogScraper.invoke_parseProgramRequirementsHTML_forTests(
            dsuCyberDefenseSnippet,
            baseURL: "https://catalog.dsu.edu/preview_program.php?catoid=45&poid=3975"
        )
        let chooseRows = parsed.requirements.filter { ($0.selectCount ?? 0) > 0 }
        XCTAssertFalse(chooseRows.isEmpty)
        for row in chooseRows where row.selectFrom?.isEmpty ?? true {
            XCTAssertEqual(row.requirementKind, .ruleBucket)
        }
    }

    func testParseFullDSUCyberDefenseCatalogFixture() throws {
        let fixtureURL = Bundle(for: DSUProgramRequirementsParserTests.self)
            .url(forResource: "DSUCyberDefenseMS3975", withExtension: "html", subdirectory: "Fixtures")
            ?? Bundle(for: DSUProgramRequirementsParserTests.self)
                .url(forResource: "DSUCyberDefenseMS3975", withExtension: "html")
        guard let fixtureURL else {
            throw XCTSkip("Missing CollegeTests/Fixtures/DSUCyberDefenseMS3975.html")
        }
        let html = try String(contentsOf: fixtureURL, encoding: .utf8)
        let parsed = try UniversalCatalogScraper.invoke_parseProgramRequirementsHTML_forTests(
            html,
            baseURL: "https://catalog.dsu.edu/preview_program.php?catoid=45&poid=3975"
        )
        XCTAssertGreaterThan(
            parsed.requirements.count,
            3,
            "Expected Required Core, specializations, and elective rules from live DSU page"
        )
        let categories = Set(parsed.requirements.map(\.category))
        XCTAssertTrue(categories.contains(where: { $0.localizedCaseInsensitiveContains("Required Core") }))
        XCTAssertTrue(categories.contains(where: { $0.localizedCaseInsensitiveContains("Knowledge Courses") }))
    }

    func testParseFullDSUCyberDefenseFixture_specializationsRetainTheirCourses() throws {
        let fixtureURL = Bundle(for: DSUProgramRequirementsParserTests.self)
            .url(forResource: "DSUCyberDefenseMS3975", withExtension: "html", subdirectory: "Fixtures")
            ?? Bundle(for: DSUProgramRequirementsParserTests.self)
                .url(forResource: "DSUCyberDefenseMS3975", withExtension: "html")
        guard let fixtureURL else { throw XCTSkip("Missing CollegeTests/Fixtures/DSUCyberDefenseMS3975.html") }
        let html = try String(contentsOf: fixtureURL, encoding: .utf8)
        let parsed = try UniversalCatalogScraper.invoke_parseProgramRequirementsHTML_forTests(
            html,
            baseURL: "https://catalog.dsu.edu/preview_program.php?catoid=45&poid=3975"
        )

        func courses(in categoryFragment: String) -> Set<String> {
            let row = parsed.requirements.first { $0.category.localizedCaseInsensitiveContains(categoryFragment) }
            return Set(row?.requiredCourses ?? [])
        }

        let security = courses(in: "Security Management and Compliance Specialization")
        XCTAssertTrue(security.isSuperset(of: ["INFA 720", "INFA 722", "INFA 742", "INFA 745"]),
                      "Security specialization lost its course list: \(security)")

        let technical = courses(in: "Technical Specialization")
        XCTAssertTrue(technical.isSuperset(of: ["INFA 721", "INFA 723", "INFA 732", "INFA 751"]),
                      "Technical specialization lost its course list: \(technical)")

        let choiceParent = "Choose one of the following Specializations 18 credits"
        let securityRow = parsed.requirements.first {
            $0.category.localizedCaseInsensitiveContains("Security Management and Compliance Specialization")
        }
        let technicalRow = parsed.requirements.first {
            $0.category.localizedCaseInsensitiveContains("Technical Specialization")
        }
        XCTAssertEqual(securityRow?.parentCategory, choiceParent)
        XCTAssertEqual(securityRow?.displayTitle, "Security Management and Compliance Specialization")
        XCTAssertEqual(technicalRow?.parentCategory, choiceParent)
        XCTAssertEqual(technicalRow?.displayTitle, "Technical Specialization")

        let openEndedSpecializationRules = parsed.requirements.filter {
            $0.category.localizedCaseInsensitiveContains("Choose two 700-800")
        }
        XCTAssertEqual(openEndedSpecializationRules.count, 2)
        XCTAssertTrue(openEndedSpecializationRules.allSatisfy { $0.parentCategory == choiceParent })
    }

    func testParseProgramRequirements_extractsCreditsOnCourseDetails() throws {
        let parsed = try UniversalCatalogScraper.invoke_parseProgramRequirementsHTML_forTests(
            dsuCyberDefenseSnippet,
            baseURL: "https://catalog.dsu.edu"
        )
        let core = parsed.requirements.first { $0.category.localizedCaseInsensitiveContains("Required Core") }
        let detailed = core?.requiredCoursesDetailed ?? []
        let infa702 = detailed.first { $0.code == "INFA 702" }
        XCTAssertEqual(infa702?.credits, "3")
    }
}
