// CatalogEntityIdentityTests.swift
// Feature: Shared
// Purpose: Catalog entity identity matcher — stable ID reuse across syncs.
// Data: CollegePersistence / repositories when applicable.

import XCTest
@testable import College

final class CatalogEntityIdentityTests: XCTestCase {
    private let versionID = "2025-undergrad"

    func testResolveProgramIdentity_reusesStableIDOnURLMatch() {
        let existing = CatalogEntityIdentity(
            stableID: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            entityType: .program,
            catalogVersionID: versionID,
            displayKey: "bulletin.example.edu/programs/cs|major"
        )
        let resolved = CatalogEntityIdentityMatcher.resolveProgramIdentity(
            url: "https://bulletin.example.edu/programs/cs/",
            name: "Computer Science",
            type: "Major",
            catalogVersionID: versionID,
            existing: [existing]
        )
        XCTAssertEqual(resolved.stableID, existing.stableID)
    }

    func testResolveProgramIdentity_reusesStableIDOnRename() {
        let stable = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let existing = CatalogEntityIdentity(
            stableID: stable,
            entityType: .program,
            catalogVersionID: versionID,
            displayKey: "bulletin.example.edu/programs/cs|computer science"
        )
        let resolved = CatalogEntityIdentityMatcher.resolveProgramIdentity(
            url: "https://bulletin.example.edu/programs/cs/",
            name: "Computer Science B.S.",
            type: "Major",
            catalogVersionID: versionID,
            existing: [existing]
        )
        XCTAssertEqual(resolved.stableID, stable)
    }

    func testMatchProgram_fuzzyTitleWhenURLDiffers() {
        let existing = CatalogEntityIdentity(
            stableID: UUID(),
            entityType: .program,
            catalogVersionID: versionID,
            displayKey: "bulletin.example.edu/old-path|computer science bs"
        )
        let matched = CatalogEntityIdentityMatcher.matchProgram(
            url: "https://bulletin.example.edu/new-path/",
            name: "Computer Science BS",
            type: "computer science bs",
            catalogVersionID: versionID,
            existing: [existing]
        )
        XCTAssertNotNil(matched)
    }

    func testResolveCourseIdentity_reusesOnNormalizedCode() {
        let stable = UUID()
        let existing = CatalogEntityIdentity(
            stableID: stable,
            entityType: .course,
            catalogVersionID: versionID,
            displayKey: CatalogEntityIdentityMatcher.displayKeyForCourse(courseCode: "CSE 115")
        )
        let resolved = CatalogEntityIdentityMatcher.resolveCourseIdentity(
            courseCode: "CSE 115",
            catalogVersionID: versionID,
            existing: [existing]
        )
        XCTAssertEqual(resolved.stableID, stable)
    }
}
