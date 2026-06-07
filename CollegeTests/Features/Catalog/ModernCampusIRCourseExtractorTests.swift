// ModernCampusIRCourseExtractorTests.swift
// Feature: Shared
// Purpose: MC Document IR → course stub extraction.

import XCTest
@testable import College

final class ModernCampusIRCourseExtractorTests: XCTestCase {
    func testCoursesFromIR_parsesPreviewCourseLink() {
        let node = CatalogDocumentNode(
            depth: 1,
            kind: .courseBlock,
            text: "CSE 115 — Intro to CS",
            sourceURL: "https://catalog.example.edu/preview_course_nopop.php?catoid=1&coid=99",
            elementSignature: "a.preview_course",
            sectionLabel: .courses
        )
        let ir = CatalogDocumentIR.build(
            schoolID: "test",
            catalogVersionID: "v1",
            engine: "moderncampus",
            layoutProfileID: "sidebarN2Links",
            nodes: [node],
            layoutConfidence: CatalogExtractionConfidence(score: 0.8, reasons: ["test"])
        )
        let courses = ModernCampusIRCourseExtractor.courses(from: ir)
        XCTAssertEqual(courses.count, 1)
        XCTAssertEqual(courses.first?.courseCode, "CSE 115")
        XCTAssertEqual(courses.first?.title, "Intro to CS")
    }
}
