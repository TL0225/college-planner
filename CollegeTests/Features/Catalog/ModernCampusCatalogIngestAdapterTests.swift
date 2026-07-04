// ModernCampusCatalogIngestAdapterTests.swift
// Feature: Shared
// Purpose: MC IR course merge + fallback thresholds.

import XCTest
@testable import College

final class ModernCampusCatalogIngestAdapterTests: XCTestCase {
    func testShouldFallbackToUniversalScraperForCourses_whenSparse() {
        XCTAssertTrue(ModernCampusCatalogIngestAdapter.shouldFallbackToUniversalScraperForCourses(irCourseCount: 0))
        XCTAssertTrue(ModernCampusCatalogIngestAdapter.shouldFallbackToUniversalScraperForCourses(irCourseCount: 10))
        XCTAssertFalse(ModernCampusCatalogIngestAdapter.shouldFallbackToUniversalScraperForCourses(irCourseCount: 30))
    }

    func testMergeCourses_prefersPrimaryAndFillsGaps() {
        let primary = [
            CatalogCourse(courseCode: "CSE 115", title: "Intro", credits: 3)
        ]
        let fallback = [
            CatalogCourse(courseCode: "CSE 116", title: "Stub", credits: 0),
            CatalogCourse(courseCode: "CSE 115", title: "Duplicate", credits: 0)
        ]
        let merged = ModernCampusCatalogIngestAdapter.mergeCourses(primary: primary, irFallback: fallback)
        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged.first(where: { $0.courseCode == "CSE 115" })?.credits, 3)
    }

    func testClassifyPageKind_withoutLabel_doesNotMatchProgramListing() {
        let url = "https://catalog.dsu.edu/content.php?catoid=44&navoid=2444"
        XCTAssertEqual(
            ModernCampusCatalogDiscoverer.classifyPageKind(url: url),
            .unknown,
            "URL-only classification must not guess program listing without sidebar label"
        )
        XCTAssertEqual(
            ModernCampusCatalogDiscoverer.classifyPageKind(url: url, linkLabel: "Academic Programs"),
            .programListing
        )
    }
}
