// CatalogPDFCourseFormatDetectorTests.swift
// Feature: Catalog
// Purpose: Unit tests for adaptive course grammar detection.

import XCTest
@testable import College

final class CatalogPDFCourseFormatDetectorTests: XCTestCase {
    func testDetectsFordhamInlineGrammarWithHighConfidence() {
        let text = (0..<40).map { idx in
            "AIGB \(7200 + idx). Sample Course \(idx). (3 Credits)\nDescription for course \(idx)."
        }.joined(separator: "\n")

        let result = CatalogPDFCourseFormatDetector.detect(sectionText: text)
        XCTAssertEqual(result.grammar.header.codeShape, .alphaNumDot)
        XCTAssertEqual(result.grammar.metadata, .inlineParenthetical)
        XCTAssertGreaterThan(result.confidence, 0.8)
    }

    func testDetectsCMUTermUnitsGrammarWithHighConfidence() {
        let text = (0..<40).map { idx in
            """
            69-\(String(format: "%03d", idx)) Sample Course \(idx)
            Fall and Spring: 3 units
            "Description for course \(idx)."
            """
        }.joined(separator: "\n")

        let result = CatalogPDFCourseFormatDetector.detect(sectionText: text)
        XCTAssertEqual(result.grammar.header.codeShape, .numNum)
        XCTAssertEqual(result.grammar.metadata, .nextLineTermUnits)
        XCTAssertGreaterThan(result.confidence, 0.8)
    }

    func testDetectsBrooklynHoursCreditsGrammarWithHighConfidence() {
        let text = (0..<40).map { idx in
            """
            CISC \(2200 + idx) Sample Brooklyn Course \(idx)
            3 hours; 3 credits
            Description body for course \(idx).
            """
        }.joined(separator: "\n")

        let result = CatalogPDFCourseFormatDetector.detect(sectionText: text)
        XCTAssertEqual(result.grammar.header.codeShape, .alphaNum)
        XCTAssertEqual(result.grammar.metadata, .nextLineHoursCredits)
        XCTAssertGreaterThan(result.confidence, 0.8)
    }

    func testAmbiguousSampleYieldsLowerConfidenceThanClearWinner() {
        let clear = CatalogPDFCourseFormatDetector.detect(sectionText: String(repeating: "69-097 Introduction to Horseback Riding\nFall and Spring: 3 units\nDesc.\n", count: 50))
        let ambiguous = CatalogPDFCourseFormatDetector.detect(sectionText: """
            ACCT 2001 Principles of Accounting I
            3 hours; 3 credits
            69-097 Introduction to Horseback Riding
            Fall and Spring: 3 units
            AIGB 7290. Deep Learning. (3 Credits)
            """)

        XCTAssertGreaterThan(clear.confidence, ambiguous.confidence)
    }

    func testTermUnitsMetadataLineExtractsCredits() {
        XCTAssertTrue(
            CatalogPDFCourseFormatDetector.lineLooksLikeMetadata(
                "Fall and Spring: 3 units",
                metadata: .nextLineTermUnits
            )
        )
        XCTAssertEqual(
            CatalogPDFCourseFormatDetector.extractCredits(from: "Fall and Spring: 3 units", metadata: .nextLineTermUnits),
            3
        )
    }

    func testTrailingUnitsRangeExtractsCreditsFromHeaderLine() {
        XCTAssertEqual(
            CatalogPDFCourseFormatDetector.extractTrailingUnits(from: "Modern Biology 9-10")?.credits,
            9
        )
        XCTAssertEqual(
            CatalogPDFCourseFormatDetector.extractTrailingUnits(from: "Modern Biology 9-10")?.title,
            "Modern Biology"
        )
        XCTAssertNil(CatalogPDFCourseFormatDetector.extractTrailingUnits(from: "Introduction to Horseback Riding"))
    }
}
