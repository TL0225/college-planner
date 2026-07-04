// CatalogPDFProgramExtractorTests.swift
// Feature: Catalog
// Purpose: Unit tests for outline-driven program extraction.

import XCTest
@testable import College

final class CatalogPDFProgramExtractorTests: XCTestCase {
    func testParsesCommaDegreeSuffixOutlineTitle() {
        let entry = CatalogPDFOutlineEntry(title: "Computer Science, B.S.", pageIndex: 12, depth: 1)
        let program = CatalogPDFProgramExtractor.extractFromOutline(
            entries: [entry],
            sourceURL: URL(fileURLWithPath: "/tmp/sample.pdf")
        ).first

        XCTAssertEqual(program?.name, "Computer Science")
        XCTAssertEqual(program?.type, "Major")
        XCTAssertEqual(program?.degreeType, "BS")
    }

    func testParsesBachelorOfScienceInOutlineTitle() {
        let entry = CatalogPDFOutlineEntry(title: "Bachelor of Science in Electrical Engineering", pageIndex: 4, depth: 1)
        let program = CatalogPDFProgramExtractor.extractFromOutline(
            entries: [entry],
            sourceURL: URL(fileURLWithPath: "/tmp/sample.pdf")
        ).first

        XCTAssertEqual(program?.name, "Electrical Engineering")
        XCTAssertEqual(program?.type, "Major")
        XCTAssertEqual(program?.degreeType, "BS")
    }

    func testRejectsDepartmentOutlineTitle() {
        let entry = CatalogPDFOutlineEntry(title: "Department of Computer Science", pageIndex: 4, depth: 1)
        let programs = CatalogPDFProgramExtractor.extractFromOutline(
            entries: [entry],
            sourceURL: URL(fileURLWithPath: "/tmp/sample.pdf")
        )
        XCTAssertTrue(programs.isEmpty)
    }

    func testParsesNamedProgramOutlineTitle() {
        let entry = CatalogPDFOutlineEntry(title: "Computer Science Program", pageIndex: 800, depth: 2)
        let program = CatalogPDFProgramExtractor.extractFromOutline(
            entries: [entry],
            sourceURL: URL(fileURLWithPath: "/tmp/sample.pdf")
        ).first

        XCTAssertEqual(program?.name, "Computer Science")
        XCTAssertEqual(program?.type, "Major")
    }

    func testRejectsProgramCoursesOutlineTitle() {
        let entry = CatalogPDFOutlineEntry(title: "Information Systems Program Courses", pageIndex: 480, depth: 3)
        let programs = CatalogPDFProgramExtractor.extractFromOutline(
            entries: [entry],
            sourceURL: URL(fileURLWithPath: "/tmp/sample.pdf")
        )
        XCTAssertTrue(programs.isEmpty)
    }

    func testRejectsPluralProgramsGroupingOutlineTitle() {
        let entry = CatalogPDFOutlineEntry(title: "Interdisciplinary Programs", pageIndex: 886, depth: 1)
        let programs = CatalogPDFProgramExtractor.extractFromOutline(
            entries: [entry],
            sourceURL: URL(fileURLWithPath: "/tmp/sample.pdf")
        )
        XCTAssertTrue(programs.isEmpty)
    }

    func testRejectsCatalogTitleNoiseFromOutline() {
        let entry = CatalogPDFOutlineEntry(
            title: "CarnegieMellonUniversity2025-2026UndergraduateCatalog 931",
            pageIndex: 930,
            depth: 1
        )
        let programs = CatalogPDFProgramExtractor.extractFromOutline(
            entries: [entry],
            sourceURL: URL(fileURLWithPath: "/tmp/sample.pdf")
        )
        XCTAssertTrue(programs.isEmpty)
    }

    func testRejectsAllCapsBannerFromOutline() {
        let entry = CatalogPDFOutlineEntry(title: "COLLEGE OF FINE ARTS", pageIndex: 233, depth: 1)
        let programs = CatalogPDFProgramExtractor.extractFromOutline(
            entries: [entry],
            sourceURL: URL(fileURLWithPath: "/tmp/sample.pdf")
        )
        XCTAssertTrue(programs.isEmpty)
    }
}
