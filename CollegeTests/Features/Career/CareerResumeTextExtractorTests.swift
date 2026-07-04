// CareerResumeTextExtractorTests.swift
// Feature: Career
// Purpose: Resume PDF text extraction regression tests.

import XCTest
@testable import College

final class CareerResumeTextExtractorTests: XCTestCase {
    func testExtract_textBasedPDFFromVaultStyleTempFile() async throws {
        let source = try ResumePDFTestFixtures.materializeSamplePDF()
        defer { try? FileManager.default.removeItem(at: source) }

        let vaultStyleURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString)-resume-fixture.pdf")
        defer { try? FileManager.default.removeItem(at: vaultStyleURL) }
        try Data(contentsOf: source).write(to: vaultStyleURL, options: [.atomic])

        let result = await CareerResumeTextExtractor.extract(from: vaultStyleURL)
        XCTAssertGreaterThan(result.plainText.count, 500)
        XCTAssertFalse(result.usedOCR)

        let report = CareerResumeParserCompliance.analyze(
            plainText: result.plainText,
            pageCount: result.pageCount,
            usedOCR: result.usedOCR
        )
        XCTAssertGreaterThan(report.healthPercent, 70)
        XCTAssertFalse(report.issues.contains(where: { $0.code == "sparse_text" }))
    }
}
