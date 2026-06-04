// CatalogIngestFreshnessTests.swift
// Feature: Catalog
// Purpose: Catalog module — CatalogIngestFreshnessTests.
// Data: CollegePersistence / repositories when applicable.

import XCTest
@testable import College

@MainActor
final class CatalogIngestFreshnessTests: XCTestCase {
    func testForceNextRescrapeConsumedOnce() {
        CatalogBackgroundSyncRunner.setForceNextRescrape(true)

        XCTAssertTrue(CatalogBackgroundSyncRunner.consumeForceNextRescrapeIfNeeded())
        XCTAssertFalse(CatalogBackgroundSyncRunner.consumeForceNextRescrapeIfNeeded())
    }

    func testPartialImportDoesNotArchiveExistingCourses() async throws {
        throw XCTSkip("Follow-up fixture setup required for local store catalog import isolation in CI.")
    }
}
