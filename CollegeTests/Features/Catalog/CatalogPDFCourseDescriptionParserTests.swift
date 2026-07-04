// CatalogPDFCourseDescriptionParserTests.swift
// Feature: Catalog
// Purpose: Verify block-structured course description parsing (titles, credits, descriptions, prereqs).

import XCTest
@testable import College

final class CatalogPDFCourseDescriptionParserTests: XCTestCase {
    private var fordhamGrammar: CatalogPDFCourseEntryGrammar {
        CatalogPDFCourseEntryGrammar(
            header: .builtin(for: .alphaNumDot),
            metadata: .inlineParenthetical
        )
    }

    func testNumNumHeaderRegexMatchesSampleLine() {
        let pattern = #"^(\d{2})-(\d{3})\s+(.*)$"#
        let line = "69-097 Introduction to Horseback Riding"
        let regex = try! NSRegularExpression(pattern: pattern)
        let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..<line.endIndex, in: line))
        XCTAssertNotNil(match)
        XCTAssertEqual(match?.numberOfRanges, 4)
    }

    func testParsesFordhamInlineMinimalBlock() {
        let text = "AIGB 7290. Deep Learning. (3 Credits)\nDescription line."
        let header = CatalogPDFCourseDescriptionParser.matchHeader(
            "AIGB 7290. Deep Learning. (3 Credits)",
            grammar: .builtin(for: .alphaNumDot)
        )
        XCTAssertNotNil(header)
        let result = CatalogPDFCourseDescriptionParser.parseBlocks(sectionText: text, grammar: fordhamGrammar)
        if result.courses.count != 1 {
            XCTFail("count=\(result.courses.count) failed=\(result.failedHeaders) header=\(String(describing: header))")
        }
        XCTAssertEqual(result.courses.first?.courseCode, "AIGB 7290")
        XCTAssertEqual(result.courses.first?.title, "Deep Learning")
        XCTAssertEqual(result.courses.first?.credits, 3)
    }

    func testParsesTitleCreditsDescriptionAndPrerequisites() {
        let text = """
        AIGB 7290. Deep Learning. (3 Credits)
        The goal of this course is to acquaint students with the objectives
        and methods of deep machine learning (DML).
        Attributes: AICE, AIEL, AITE.
        Prerequisites: AIGB 6200 or AIGB 6201 or ISGB 7943.
        """

        let courses = CatalogPDFCourseDescriptionParser.parse(sectionText: text, grammar: fordhamGrammar)
        XCTAssertEqual(courses.count, 1)
        let course = try! XCTUnwrap(courses.first)

        XCTAssertEqual(course.courseCode, "AIGB 7290")
        XCTAssertEqual(course.title, "Deep Learning")
        XCTAssertEqual(course.credits, 3)
        XCTAssertEqual(course.department, "AIGB")
        XCTAssertNotNil(course.description)
        XCTAssertTrue(course.description?.contains("deep machine learning") == true)
        // Attributes are catalog tags and must not leak into the human-readable description.
        XCTAssertFalse(course.description?.contains("AICE") == true)
        XCTAssertEqual(course.prerequisiteText, "AIGB 6200 or AIGB 6201 or ISGB 7943.")

        // All-OR prerequisite prose yields an `.or` structured rule.
        guard case .or(let rules)? = course.prerequisites else {
            return XCTFail("Expected an OR prerequisite rule, got \(String(describing: course.prerequisites))")
        }
        XCTAssertEqual(rules.count, 3)
    }

    func testHandlesCreditsWrappingAcrossLines() {
        // Mirrors PDFKit output where "(3" ends one line and "Credits)" begins the next.
        let text = """
        AIGB 7264. Strategies for Technological Innovation and Change. (3
        Credits)
        This course relies on fundamental concepts in economics and strategy.
        """

        let courses = CatalogPDFCourseDescriptionParser.parse(sectionText: text, grammar: fordhamGrammar)
        let course = try! XCTUnwrap(courses.first)
        XCTAssertEqual(course.courseCode, "AIGB 7264")
        XCTAssertEqual(course.title, "Strategies for Technological Innovation and Change")
        XCTAssertEqual(course.credits, 3)
    }

    func testAlphanumericCourseNumbersAreNotCollapsed() {
        // 726A and 726B must remain distinct (legacy regex collapsed both to 726).
        let text = """
        AIGB 726A. AI for Strategic Decision Making. (3 Credits)
        Managers use machine learning techniques for value-chain decisions.
        AIGB 726B. Navigating AI Disruption. (3 Credits)
        Forward-thinking leaders learn to navigate technological disruption.
        """

        let courses = CatalogPDFCourseDescriptionParser.parse(sectionText: text, grammar: fordhamGrammar)
        let codes = Set(courses.map(\.courseCode))
        XCTAssertTrue(codes.contains("AIGB 726A"))
        XCTAssertTrue(codes.contains("AIGB 726B"))
        XCTAssertEqual(courses.count, 2)
    }

    func testCapturesCorequisites() {
        let text = """
        ACGB 719W. Professional Competencies for Accounting Licensure. (3 Credits)
        This course integrates advanced accounting theory with professional competencies.
        Corequisite: ACGB 7125.
        """

        let course = try! XCTUnwrap(CatalogPDFCourseDescriptionParser.parse(sectionText: text, grammar: fordhamGrammar).first)
        XCTAssertEqual(course.corequisites, ["ACGB 7125"])
    }

    func testStripsPageFurnitureFromDescriptionAndPrereqs() {
        let text = """
        ACGB 719E. Data-Based Operation Controls. (3 Credits)
        The primary focus of the class will be on data-driven analytics.
        Prerequisites: ACGB 7155.
        Updated: 01-22-2026
        986 Accounting (Graduate) (ACGB)
        ACGB 719F. Data Analytics. (3 Credits)
        A follow-on analytics course.
        """

        let courses = CatalogPDFCourseDescriptionParser.parse(sectionText: text, grammar: fordhamGrammar)
        let first = try! XCTUnwrap(courses.first { $0.courseCode == "ACGB 719E" })
        XCTAssertEqual(first.prerequisiteText, "ACGB 7155.")
        XCTAssertFalse(first.description?.contains("Updated") == true)
        XCTAssertFalse(first.prerequisiteText?.contains("Updated") == true)
        XCTAssertEqual(courses.count, 2)
    }

    func testIgnoresIndexAndHeadingNoise() {
        let text = """
        A
        • Accounting (Graduate) (ACGB) (p. 984)
        Accounting (Graduate) (ACGB)
        ACGB 7100. Financial Accounting. (3 Credits)
        Introduces the conceptual framework of financial accounting.
        """

        let courses = CatalogPDFCourseDescriptionParser.parse(sectionText: text, grammar: fordhamGrammar)
        XCTAssertEqual(courses.count, 1)
        XCTAssertEqual(courses.first?.courseCode, "ACGB 7100")
        XCTAssertEqual(courses.first?.description, "Introduces the conceptual framework of financial accounting.")
    }

    func testMatchHeaderNumNumLine() {
        let header = CatalogPDFCourseDescriptionParser.matchHeader(
            "69-097 Introduction to Horseback Riding",
            grammar: .builtin(for: .numNum)
        )
        XCTAssertNotNil(header)
        XCTAssertEqual(header?.courseCode, "69-097")
    }

    func testParsesMinimalCMUTermUnitsBlock() {
        let text = "69-097 Introduction to Horseback Riding\nFall and Spring: 3 units\nBody text."
        let grammar = CatalogPDFCourseEntryGrammar(
            header: .builtin(for: .numNum),
            metadata: .nextLineTermUnits
        )
        let result = CatalogPDFCourseDescriptionParser.parseBlocks(sectionText: text, grammar: grammar)
        if result.courses.isEmpty {
            XCTFail("empty courses failedHeaders=\(result.failedHeaders)")
        }
        XCTAssertEqual(result.courses.count, 1)
        XCTAssertEqual(result.courses.first?.credits, 3)
        XCTAssertEqual(result.courses.first?.title, "Introduction to Horseback Riding")
    }

    func testParsesCMUTermUnitsBlock() {
        let text = """
        69-097 Introduction to Horseback Riding
        Fall and Spring: 3 units
        "This full semester course is designed for beginners who want to learn
        the fundamentals of horseback riding."
        """

        let grammar = CatalogPDFCourseEntryGrammar(
            header: .builtin(for: .numNum),
            metadata: .nextLineTermUnits
        )
        let courses = CatalogPDFCourseDescriptionParser.parse(sectionText: text, grammar: grammar)
        let course = try! XCTUnwrap(courses.first)
        XCTAssertEqual(courses.count, 1)
        XCTAssertEqual(course.courseCode, "69-097")
        XCTAssertEqual(course.title, "Introduction to Horseback Riding")
        XCTAssertEqual(course.credits, 3)
        XCTAssertTrue(course.description?.contains("horseback riding") == true)
    }

    func testParsesBrooklynHoursCreditsBlock() {
        let text = """
        ACCT 2001 Principles of Accounting I (Financial)
        3 hours; 3 credits
        Introduction to the concepts and principles of financial
        accounting. Techniques of data accumulation.
        """

        let grammar = CatalogPDFCourseEntryGrammar(
            header: .builtin(for: .alphaNum),
            metadata: .nextLineHoursCredits
        )
        let course = try! XCTUnwrap(CatalogPDFCourseDescriptionParser.parse(sectionText: text, grammar: grammar).first)
        XCTAssertEqual(course.courseCode, "ACCT 2001")
        XCTAssertTrue(course.title.contains("Principles of Accounting I"))
        XCTAssertEqual(course.credits, 3)
        XCTAssertTrue(course.description?.contains("financial") == true)
    }

    func testParsesCMUSplitHeaderWithTermUnitsOnNextLine() {
        let text = """
        21-127 Concepts of Mathematics
        All Semesters: 12 units
        "This course introduces the basic concepts, ideas and tools involved in
        doing mathematics."
        """

        let grammar = CatalogPDFCourseEntryGrammar(
            header: .builtin(for: .numNum),
            metadata: .trailingUnitsRange
        )
        let course = try! XCTUnwrap(CatalogPDFCourseDescriptionParser.parse(sectionText: text, grammar: grammar).first)
        XCTAssertEqual(course.courseCode, "21-127")
        XCTAssertEqual(course.title, "Concepts of Mathematics")
        XCTAssertEqual(course.credits, 12)
        XCTAssertTrue(course.description?.contains("basic concepts") == true)
    }

    func testParsesCMUTrailingUnitsOnHeaderLine() {
        let text = """
        03-121 Modern Biology 9-10
        "This course covers the fundamentals of modern biology."
        """

        let grammar = CatalogPDFCourseEntryGrammar(
            header: .builtin(for: .numNum),
            metadata: .trailingUnitsRange
        )
        let course = try! XCTUnwrap(CatalogPDFCourseDescriptionParser.parse(sectionText: text, grammar: grammar).first)
        XCTAssertEqual(course.courseCode, "03-121")
        XCTAssertEqual(course.title, "Modern Biology")
        XCTAssertEqual(course.credits, 9)
    }

    func testBrooklynCreditValueWrapsBelowHoursClause() {
        // Internship entries push the credit onto its own line after a long hours clause.
        let text = """
        ACCT 5200 Accounting Internship
        9 hours average weekly field work, totalling at least 135 hours;
        3 credits
        An off-campus internship supervised and approved by a faculty member.
        """

        let grammar = CatalogPDFCourseEntryGrammar(
            header: .builtin(for: .alphaNum),
            metadata: .nextLineHoursCredits
        )
        let course = try! XCTUnwrap(CatalogPDFCourseDescriptionParser.parse(sectionText: text, grammar: grammar).first)
        XCTAssertEqual(course.courseCode, "ACCT 5200")
        XCTAssertEqual(course.title, "Accounting Internship")
        XCTAssertEqual(course.credits, 3)
        XCTAssertTrue(course.description?.contains("off-campus internship") == true)
    }

    func testBrooklynSplitCreditTokenAcrossLines() {
        // PDFKit splits the value and the word: "…); 3" then "credits".
        let text = """
        ARTD 3414 Mural Art
        4 hours (1 hour recitation, 1 hour lecture, 2 hours
        laboratory/studio, minimum of 4 hours independent work); 3
        credits
        Mural painting, including brainstorming concepts and community engagement.
        """

        let grammar = CatalogPDFCourseEntryGrammar(
            header: .builtin(for: .alphaNum),
            metadata: .nextLineHoursCredits
        )
        let course = try! XCTUnwrap(CatalogPDFCourseDescriptionParser.parse(sectionText: text, grammar: grammar).first)
        XCTAssertEqual(course.credits, 3)
        XCTAssertTrue(course.description?.contains("Mural painting") == true)
    }

    func testBrooklynSpelledOutHoursStillResolvesCredit() {
        let text = """
        AFST 5403W Independent Research and Writing
        Minimum of nine hours conference and independent work; 3
        credits
        Independent research project supervised by a faculty member.
        """

        let grammar = CatalogPDFCourseEntryGrammar(
            header: .builtin(for: .alphaNum),
            metadata: .nextLineHoursCredits
        )
        let course = try! XCTUnwrap(CatalogPDFCourseDescriptionParser.parse(sectionText: text, grammar: grammar).first)
        XCTAssertEqual(course.credits, 3)
    }

    func testBrooklynCreditSurvivesPaginationNoiseBetweenValueAndWord() {
        // A page break injects running headers between "…; 3" and "credits".
        let text = """
        LATN 4170 Studies in Latin
        Minimum 9 hours of conference and independent work; 3
        Programs and Courses of Instruction
        Classics 179
        credits
        Studies in grammar, syntax and morphology aimed at building proficiency.
        """

        let grammar = CatalogPDFCourseEntryGrammar(
            header: .builtin(for: .alphaNum),
            metadata: .nextLineHoursCredits
        )
        let course = try! XCTUnwrap(CatalogPDFCourseDescriptionParser.parse(sectionText: text, grammar: grammar).first)
        XCTAssertEqual(course.credits, 3)
        XCTAssertTrue(course.description?.contains("grammar") == true)
    }

    func testFordhamVariableCreditRangeUsesUpperBound() {
        // "(0 to 4 Credits)" is a graded variable-credit course, not a zero-credit one.
        let text = """
        BISC 4999. Research Tutorial. (0 to 4 Credits)
        Hands-on independent research with a faculty mentor.
        """

        let course = try! XCTUnwrap(CatalogPDFCourseDescriptionParser.parse(sectionText: text, grammar: fordhamGrammar).first)
        XCTAssertEqual(course.courseCode, "BISC 4999")
        XCTAssertEqual(course.credits, 4)
    }

    func testParsesBrooklynCommaSeparatedHoursCredits() {
        let text = """
        HIST 3001 Advanced Historical Research
        3 hours, 3 credits
        Research methods for history majors.
        """

        let grammar = CatalogPDFCourseEntryGrammar(
            header: .builtin(for: .alphaNum),
            metadata: .nextLineHoursCredits
        )
        let course = try! XCTUnwrap(CatalogPDFCourseDescriptionParser.parse(sectionText: text, grammar: grammar).first)
        XCTAssertEqual(course.credits, 3)
    }

    func testBrooklynUndergradPipelineExtractsManyCourses() async throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let pdfURL = repoRoot.appendingPathComponent("docs/pdf-baselines/brooklyn-undergrad.pdf")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: pdfURL.path))

        let output = try await CatalogPDFPipeline.run(
            pdfURL: pdfURL,
            options: CatalogPDFPipeline.Options(
                schoolID: "brooklyn_college",
                includeCourses: true,
                includePolicies: false,
                ocrFallback: false
            )
        )
        XCTAssertGreaterThan(output.courses.count, 2000)
    }
}
