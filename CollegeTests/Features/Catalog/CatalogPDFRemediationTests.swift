// CatalogPDFRemediationTests.swift
// Feature: Catalog
// Purpose: Regression tests for catalog PDF scraper remediation.
// Data: CollegePersistence / repositories when applicable.

import XCTest
@testable import College

final class CatalogPDFRemediationTests: XCTestCase {
    func testLayoutReconstructor_splitsOnIndentDecrease() {
        let lines = [
            CatalogPDFLine(text: "PROGRAMS", pageIndex: 0, lineIndexOnPage: 0, indentLevel: 0),
            CatalogPDFLine(text: "Bachelor of Science", pageIndex: 0, lineIndexOnPage: 1, indentLevel: 2),
            CatalogPDFLine(text: "Next Section", pageIndex: 0, lineIndexOnPage: 2, indentLevel: 0),
        ]
        let blocks = CatalogPDFLayoutReconstructor.reconstruct(from: lines)
        XCTAssertGreaterThanOrEqual(blocks.count, 2)
    }

    func testRequirementExtractor_returnsEmptyInsteadOfSyntheticRows() {
        let programs = [
            ScrapedProgram(
                name: "Computer Science",
                type: "Major",
                url: "pdf://test",
                degreeType: "BS"
            )
        ]
        let requirements = CatalogPDFRequirementExtractor.extractRequirements(from: programs)
        XCTAssertTrue(requirements.isEmpty)
    }

    func testProgramExtractor_doesNotInferDepartmentFromFirstWord() {
        let block = CatalogPDFTextBlock(
            lines: [CatalogPDFLine(text: "Master of Science in Cybersecurity", pageIndex: 2, lineIndexOnPage: 0)],
            pageRange: 2...2
        )
        let classified = CatalogPDFClassifiedBlock(
            block: block,
            type: .program,
            confidence: 0.9,
            headingPath: [],
            sectionKind: .programs,
            evidence: ClassificationEvidence(matchedRules: ["test"], positiveSignals: [], negativeSignals: [])
        )
        let (programs, _) = CatalogPDFProgramExtractor.extract(from: [classified], minConfidence: 0.5)
        XCTAssertEqual(programs.first?.department, nil)
    }

    func testSectionClassifier_ignoresFordhamPolicyMajorLimitTitle() {
        let classified = CatalogPDFSectionClassifier.classifyKindFromTitle("Limits on Number of Majors and Minors")
        XCTAssertNil(classified)
    }

    func testSectionClassifier_recognizesFordhamAcademicProgramTitles() {
        XCTAssertEqual(
            CatalogPDFSectionClassifier.classifyKindFromTitle("Academic Programs")?.kind,
            .programs
        )
        XCTAssertEqual(
            CatalogPDFSectionClassifier.classifyKindFromTitle("Accounting - Public Accountancy Major (CPA-150 track)")?.kind,
            .programs
        )
    }

    func testBlockClassifier_acceptsFordhamMajorTitleInProgramSection() {
        let block = CatalogPDFTextBlock(
            lines: [CatalogPDFLine(text: "Accounting - Public Accountancy Major (CPA-150 track)", pageIndex: 157, lineIndexOnPage: 0)],
            pageRange: 157...157
        )
        let sections = [
            CatalogPDFDocumentSection(kind: .programs, confidence: 0.84, startPage: 100, endPage: 982)
        ]
        let classified = CatalogPDFBlockClassifier.classify(
            blocks: [block],
            sections: sections,
            profile: CatalogPDFProfileLoader.profile(forSchoolID: "fordham_university")
        )
        XCTAssertEqual(classified.first?.type, .program)

        let (programs, _) = CatalogPDFProgramExtractor.extract(from: classified, minConfidence: 0.68)
        XCTAssertEqual(programs.first?.name, "Accounting - Public Accountancy (CPA-150 track)")
        XCTAssertEqual(programs.first?.type, "Major")
    }

    func testProgramExtractor_prefersProgramTitleLineOverPageHeader() {
        let block = CatalogPDFTextBlock(
            lines: [
                CatalogPDFLine(text: "132 Communications", pageIndex: 132, lineIndexOnPage: 0),
                CatalogPDFLine(text: "Communications Major", pageIndex: 132, lineIndexOnPage: 1),
            ],
            pageRange: 132...132
        )
        let classified = CatalogPDFClassifiedBlock(
            block: block,
            type: .program,
            confidence: 0.9,
            headingPath: [],
            sectionKind: .programs,
            evidence: ClassificationEvidence(matchedRules: ["test"], positiveSignals: [], negativeSignals: [])
        )
        let (programs, _) = CatalogPDFProgramExtractor.extract(from: [classified], minConfidence: 0.68)
        XCTAssertEqual(programs.first?.name, "Communications")
    }

    func testProgramExtractor_rejectsSentenceFragmentsFromRequirementProse() {
        let block = CatalogPDFTextBlock(
            lines: [CatalogPDFLine(text: "students must complete the following six courses for the major", pageIndex: 200, lineIndexOnPage: 0)],
            pageRange: 200...200
        )
        let classified = CatalogPDFClassifiedBlock(
            block: block,
            type: .program,
            confidence: 0.9,
            headingPath: [],
            sectionKind: .programs,
            evidence: ClassificationEvidence(matchedRules: ["test"], positiveSignals: [], negativeSignals: [])
        )
        let (programs, _) = CatalogPDFProgramExtractor.extract(from: [classified], minConfidence: 0.68)
        XCTAssertTrue(programs.isEmpty)
    }

    func testProgramExtractor_extractsCleanProgramsFromPDFOutline() throws {
        let sourceURL = try XCTUnwrap(URL(string: "file:///tmp/fordham.pdf"))
        let entries = [
            CatalogPDFOutlineEntry(title: "Limits on Number of Majors and Minors", pageIndex: 23, depth: 1),
            CatalogPDFOutlineEntry(title: "Accounting - Public Accountancy Major (CPA-150 track)", pageIndex: 157, depth: 2),
            CatalogPDFOutlineEntry(title: "Accounting Minor", pageIndex: 159, depth: 2),
            CatalogPDFOutlineEntry(title: "Accounting Minor", pageIndex: 159, depth: 2),
            CatalogPDFOutlineEntry(title: "Data Science & Quantitative Economics (M.S.)", pageIndex: 561, depth: 2),
            CatalogPDFOutlineEntry(title: "A-Z Academic Program Index", pageIndex: 519, depth: 1),
        ]

        let programs = CatalogPDFProgramExtractor.extractFromOutline(entries: entries, sourceURL: sourceURL)

        XCTAssertEqual(programs.map(\.name), [
            "Accounting",
            "Accounting - Public Accountancy (CPA-150 track)",
            "Data Science & Quantitative Economics (M.S.)",
        ])
        XCTAssertEqual(programs.map(\.type), ["Minor", "Major", "Graduate Program"])
        XCTAssertTrue(programs[1].url.hasSuffix("#page=158"))
    }

    func testDegreeLevel_mapsGraduateEducationTokensFromOutline() {
        XCTAssertEqual(DegreeConfiguration.level(for: "MST"), DegreeConfiguration.graduate)
        XCTAssertEqual(DegreeConfiguration.level(for: "MSE"), DegreeConfiguration.graduate)
        XCTAssertEqual(DegreeConfiguration.level(for: "MS"), DegreeConfiguration.graduate)
        XCTAssertEqual(DegreeConfiguration.level(for: "MSW"), DegreeConfiguration.graduate)
    }

    func testCourseExtractor_rejectsFalsePositiveChapterLine() {
        let profile = CatalogPDFProfileLoader.profile(forSchoolID: "fordham_university")
        let courses = CatalogPDFCourseExtractor.extractCourses(
            fromText: "See Chapter 12-345 for details.",
            profile: profile
        )
        XCTAssertTrue(courses.isEmpty)
    }

    func testCourseExtractor_rejectsFalsePositiveYearLine() {
        let profile = CatalogPDFProfileLoader.profile(forSchoolID: "fordham_university")
        let courses = CatalogPDFCourseExtractor.extractCourses(
            fromText: "Updated FALL 2024 bulletin.",
            profile: profile
        )
        XCTAssertTrue(courses.isEmpty)
    }

    func testCourseExtractor_parsesStandardCourseCode() {
        let profile = CatalogPDFProfileLoader.profile(forSchoolID: "fordham_university")
        let courses = CatalogPDFCourseExtractor.extractCourses(
            fromText: "CISC 1101 Introduction to Computing 3 credits",
            profile: profile
        )
        XCTAssertEqual(courses.first?.courseCode, "CISC 1101")
    }

    func testCourseExtractor_parsesCMUStyleOnlyForCMUProfile() {
        let fordham = CatalogPDFProfileLoader.profile(forSchoolID: "fordham_university")
        let fordhamCourses = CatalogPDFCourseExtractor.extractCourses(
            fromText: "21-127 Concepts of Mathematics",
            profile: fordham
        )
        XCTAssertTrue(fordhamCourses.isEmpty)

        let cmu = CatalogPDFProfileLoader.profile(forSchoolID: "carnegie_mellon_university")
        let cmuCourses = CatalogPDFCourseExtractor.extractCourses(
            fromText: "21-127 Concepts of Mathematics 9 units",
            profile: cmu
        )
        XCTAssertEqual(cmuCourses.first?.courseCode, "21-127")
    }

    func testClassificationEvidence_carriesBasicProvenance() {
        let block = CatalogPDFTextBlock(
            lines: [CatalogPDFLine(text: "CISC 1101 Intro", pageIndex: 4, lineIndexOnPage: 0)],
            pageRange: 4...4
        )
        let sections = [
            CatalogPDFDocumentSection(kind: .courseDescriptions, confidence: 0.9, startPage: 0, endPage: 10)
        ]
        let classified = CatalogPDFBlockClassifier.classify(
            blocks: [block],
            sections: sections,
            profile: CatalogPDFProfileLoader.profile(forSchoolID: "fordham_university")
        )
        XCTAssertEqual(classified.first?.evidence.sourcePage, 4)
        XCTAssertEqual(classified.first?.evidence.sourceSection, CatalogPDFSectionKind.courseDescriptions.rawValue)
        XCTAssertFalse((classified.first?.evidence.sourceText ?? "").isEmpty)
    }

    func testProgramExtractor_sortsProgramsDeterministically() {
        let make = { (text: String) -> CatalogPDFClassifiedBlock in
            CatalogPDFClassifiedBlock(
                block: CatalogPDFTextBlock(
                    lines: [CatalogPDFLine(text: text, pageIndex: 0, lineIndexOnPage: 0)],
                    pageRange: 0...0
                ),
                type: .program,
                confidence: 0.9,
                headingPath: [],
                sectionKind: .programs,
                evidence: ClassificationEvidence(matchedRules: [], positiveSignals: [], negativeSignals: [])
            )
        }
        let (programs, _) = CatalogPDFProgramExtractor.extract(
            from: [make("BS Zoology"), make("BS Accounting")],
            minConfidence: 0.5
        )
        XCTAssertEqual(programs.map(\.name), ["Accounting", "Zoology"])
    }

    func testOperationalLimits_rejectsOversizedPageCount() {
        XCTAssertThrowsError(try CatalogPDFOperationalLimits.validatePageCount(CatalogPDFOperationalLimits.maxPageCount + 1)) { error in
            guard let pdfError = error as? CatalogPDFError else {
                return XCTFail("Expected CatalogPDFError")
            }
            XCTAssertEqual(pdfError.failureClass, .extraction)
        }
    }

    func testCatalogPDFError_mapsFailureClasses() {
        XCTAssertEqual(CatalogPDFError.noProgramsExtracted.failureClass, .entityExtraction)
        XCTAssertEqual(CatalogPDFError.failedToOpenPDF.failureClass, .corruption)
        XCTAssertEqual(
            CatalogPDFError.exceededMaxPDFSize(actualBytes: 2, limitBytes: 1).failureClass,
            .download
        )
    }

    func testProfileIntegrity_allBundledProfilesAreValid() {
        let schoolIDs = [
            "fordham_university",
            "carnegie_mellon_university",
            "brooklyn_college",
            "unknown_school_example",
        ]
        for schoolID in schoolIDs {
            let profile = CatalogPDFProfileLoader.profile(forSchoolID: schoolID)
            let issues = CatalogPDFProfileLoader.validateProfileIntegrity(profile)
            XCTAssertTrue(issues.isEmpty, "Profile issues for \(schoolID): \(issues)")
        }
    }
}
