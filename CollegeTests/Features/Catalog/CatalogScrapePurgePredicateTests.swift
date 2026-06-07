// CatalogScrapePurgePredicateTests.swift
// Feature: Catalog
// Purpose: Catalog module — CatalogScrapePurgePredicateTests.
// Data: CollegePersistence / repositories when applicable.

import XCTest
@testable import College

@MainActor
final class CatalogScrapePurgePredicateTests: XCTestCase {
    func testCatalogScrapeDataPresence_doesNotCrashForNYUNeedle() {
        let manager = CollegePersistence.shared
        _ = manager.catalogScrapeDataPresence(
            forUniversityName: "New York University",
            programURLContains: "bulletins.nyu"
        )
    }

    func testProgramURLContainsPredicate_emptyNeedleDoesNotCrash() {
        let manager = CollegePersistence.shared
        _ = manager.catalogScrapeDataPresence(
            forUniversityName: "New York University",
            programURLContains: ""
        )
    }
}
