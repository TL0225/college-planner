// CatalogCourseSearchBridgeTests.swift
// Feature: Catalog
// Purpose: Catalog module — CatalogCourseSearchBridgeTests.
// Data: CollegePersistence / repositories when applicable.

import XCTest
@testable import College

final class CatalogCourseSearchBridgeTests: XCTestCase {
    @MainActor
    func testSearchWithoutActiveUniversityReturnsEmpty() {
        let hits = CatalogCourseSearchBridge.search(
            query: "MAT 101",
            limit: 10,
            persistence: CollegePersistence.shared
        )
        XCTAssertTrue(hits.isEmpty)
    }
}
