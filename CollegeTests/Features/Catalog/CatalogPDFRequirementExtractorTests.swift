// CatalogPDFRequirementExtractorTests.swift
// Feature: Catalog
// Purpose: Verify conservative, attributable degree-requirement extraction.

import XCTest
@testable import College

final class CatalogPDFRequirementExtractorTests: XCTestCase {
    private func program(_ name: String, _ degree: String? = nil) -> ScrapedProgram {
        ScrapedProgram(name: name, type: "Major", url: "pdf://v1/test/program/\(name)", degreeType: degree)
    }

    func testExtractsAttributedCourseListUnderCategory() {
        let text = """
        History
        Major Requirements
        HIST 1000 The Medieval World 4
        HIST 2000 Modern Europe 4
        """
        let requirements = CatalogPDFRequirementExtractor.extractRequirements(
            sectionText: text,
            knownPrograms: [program("History", "BA")],
            courseCatalog: []
        )
        XCTAssertEqual(requirements.count, 1)
        let req = try! XCTUnwrap(requirements.first)
        XCTAssertEqual(req.major, "History")
        XCTAssertEqual(req.category, "Major Requirements")
        XCTAssertEqual(req.degreeType, "BA")
        XCTAssertEqual(req.creditsRequired, 8)
        XCTAssertEqual(req.requiredCoursesDetailed?.count, 2)
    }

    func testDropsRowsThatCannotBeAttributedToAKnownProgram() {
        let text = """
        Some Unrecognized Heading
        Major Requirements
        HIST 1000 The Medieval World 4
        """
        let requirements = CatalogPDFRequirementExtractor.extractRequirements(
            sectionText: text,
            knownPrograms: [program("History")],
            courseCatalog: []
        )
        XCTAssertTrue(requirements.isEmpty, "No known program in context → no fabricated attribution")
    }

    func testIgnoresTableHeaderAndProseAsCategories() {
        let text = """
        History
        Course Title Credits
        HIST 1000 The Medieval World 4
        """
        let requirements = CatalogPDFRequirementExtractor.extractRequirements(
            sectionText: text,
            knownPrograms: [program("History")],
            courseCatalog: []
        )
        // The table-header line must not become a category; the row falls back to "Requirements".
        XCTAssertEqual(requirements.count, 1)
        XCTAssertEqual(requirements.first?.category, "Requirements")
    }

    func testSelectThreeHeadingMapsToSelectableRequirement() {
        let text = """
        Journalism
        Select three electives in COMC, DTEM, FITV, JOUR, or in another department
        JOUR 3001 News Reporting 4
        COMC 3247 Race and Gender in Media 4
        DTEM 3476 Social Media 4
        FITV 3500 Documentary Production 4
        """
        let requirements = CatalogPDFRequirementExtractor.extractRequirements(
            sectionText: text,
            knownPrograms: [program("Journalism", "BA")],
            courseCatalog: []
        )
        let req = try! XCTUnwrap(requirements.first)
        XCTAssertEqual(req.requirementKind, .chooseOne)
        XCTAssertEqual(req.selectCount, 3)
        XCTAssertNil(req.requiredCoursesDetailed)
        XCTAssertEqual(req.selectFromDetailed?.count, 4)
        XCTAssertEqual(req.creditsRequired, 12)
        XCTAssertEqual(req.requirementPredicate?.type, .any)
        XCTAssertEqual(req.requirementPredicate?.children?.count, 4)
        XCTAssertEqual(req.requirementPredicate?.selectCount, 3)
    }

    func testDropsOverflowingMergedGroups() {
        var lines = ["History", "Major Requirements"]
        for index in 0..<120 {
            lines.append("HIST \(1000 + index) Course Number \(index) 3")
        }
        let requirements = CatalogPDFRequirementExtractor.extractRequirements(
            sectionText: lines.joined(separator: "\n"),
            knownPrograms: [program("History")],
            courseCatalog: []
        )
        // 120 rows under one category is implausible → dropped rather than emitting wrong data.
        XCTAssertTrue(requirements.isEmpty)
    }

    func testAnchoredExtractorCarriesProgramAcrossPagesAndIgnoresRunningHeaders() {
        let lines: [CatalogPDFLine] = [
            CatalogPDFLine(text: "Computer Science", pageIndex: 0, lineIndexOnPage: 0),
            CatalogPDFLine(text: "Major Requirements", pageIndex: 0, lineIndexOnPage: 1),
            CatalogPDFLine(text: "CISC 1115 Introduction to Programming 3", pageIndex: 0, lineIndexOnPage: 2),
            // Simulated running header on next page should not re-anchor.
            CatalogPDFLine(text: "Undergraduate Bulletin 2026-2027", pageIndex: 1, lineIndexOnPage: 0),
            CatalogPDFLine(text: "Page 221", pageIndex: 1, lineIndexOnPage: 1),
            CatalogPDFLine(text: "CISC 2210 Discrete Structures 3", pageIndex: 1, lineIndexOnPage: 2),
        ]

        let requirements = CatalogPDFRequirementExtractor.extractAnchoredRequirements(
            lines: lines,
            knownPrograms: [program("Computer Science", "BS")],
            courseCatalog: [],
            subjectNameToCode: [:]
        )

        let req = try! XCTUnwrap(requirements.first)
        XCTAssertEqual(req.major, "Computer Science")
        XCTAssertEqual(req.category, "Major Requirements")
        XCTAssertEqual(req.requiredCoursesDetailed?.count, 2)
        XCTAssertEqual(req.creditsRequired, 6)
    }

    func testCanonicalizesRequirementMajorToKnownProgramAlias() {
        let programs = [
            program("Accounting - Public Accountancy (CPA-150 track)", "B.S."),
            program("English teacher", "MAT"),
        ]
        let requirements = CatalogPDFRequirementExtractor.extractRequirements(
            sectionText: """
            Public Accountancy
            Major Requirements
            ACCT 1010 Financial Accounting 3
            English
            Major Requirements
            ENGL 1100 Writing 3
            """,
            knownPrograms: programs,
            courseCatalog: []
        )
        let majors = Set(requirements.map(\.major))
        XCTAssertTrue(majors.contains("Accounting - Public Accountancy (CPA-150 track)"))
        XCTAssertTrue(majors.contains("English teacher"))
    }
}
