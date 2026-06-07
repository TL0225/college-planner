// CatalogPDFToDocumentIRAdapterTests.swift
// Feature: Shared
// Purpose: PDF classified blocks → CatalogDocumentIR mapping.
// Data: CollegePersistence / repositories when applicable.

import XCTest
@testable import College

final class CatalogPDFToDocumentIRAdapterTests: XCTestCase {
    func testBuildIR_mapsSectionsAndCourseBlock() {
        let line = CatalogPDFLine(text: "ECON 101 — Intro", pageIndex: 0, lineIndexOnPage: 0)
        let block = CatalogPDFTextBlock(lines: [line], pageRange: 0...0)
        let classified = CatalogPDFClassifiedBlock(
            block: block,
            type: .course,
            confidence: 0.9,
            headingPath: ["Courses"],
            sectionKind: .courseDescriptions,
            evidence: ClassificationEvidence(matchedRules: [], positiveSignals: [], negativeSignals: [])
        )

        let ir = CatalogPDFToDocumentIRAdapter.buildIR(
            schoolID: "test-school",
            catalogVersionID: "v1",
            sourceURL: "file:///catalog.pdf",
            classifiedBlocks: [classified],
            layoutProfileID: "pdf-test",
            layoutConfidence: 0.8
        )

        XCTAssertEqual(ir.schoolID, "test-school")
        XCTAssertEqual(ir.engine, "pdf")
        XCTAssertEqual(ir.layoutProfileID, "pdf-test")
        XCTAssertTrue(ir.nodes.contains { $0.kind == .section && $0.text == "Courses" })
        XCTAssertTrue(ir.nodes.contains { $0.kind == .courseBlock })
    }
}
