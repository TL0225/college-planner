// CatalogStructuralDiffEngineTests.swift
// Feature: Catalog
// Purpose: Structural diff via stable entity identities.

import XCTest
@testable import College

final class CatalogStructuralDiffEngineTests: XCTestCase {
    func testDiff_detectsProgramAddAndRemove() {
        let version = "2025-undergrad"
        let previous = [
            CatalogEntityIdentity(
                stableID: UUID(),
                entityType: .program,
                catalogVersionID: version,
                displayKey: "bulletin.example.edu/old|major"
            )
        ]
        let current = [
            CatalogEntityIdentity(
                stableID: UUID(),
                entityType: .program,
                catalogVersionID: version,
                displayKey: "bulletin.example.edu/new|major"
            ),
            CatalogEntityIdentity(
                stableID: UUID(),
                entityType: .course,
                catalogVersionID: version,
                displayKey: "CSE 115"
            )
        ]
        let report = CatalogStructuralDiffEngine.diff(
            schoolID: "test_school",
            catalogVersionID: version,
            previous: previous,
            current: current
        )
        XCTAssertEqual(report.programsAdded, 1)
        XCTAssertEqual(report.programsRemoved, 1)
        XCTAssertEqual(report.coursesAdded, 1)
        XCTAssertEqual(report.coursesRemoved, 0)
        XCTAssertTrue(report.hasChanges)
    }

    func testDiff_detectsRenameViaStableID() {
        let stableID = UUID()
        let version = "2025-undergrad"
        let previous = [
            CatalogEntityIdentity(
                stableID: stableID,
                entityType: .program,
                catalogVersionID: version,
                displayKey: "old-name|program"
            )
        ]
        let current = [
            CatalogEntityIdentity(
                stableID: stableID,
                entityType: .program,
                catalogVersionID: version,
                displayKey: "new-name|program"
            )
        ]
        let report = CatalogStructuralDiffEngine.diff(
            schoolID: "test_school",
            catalogVersionID: version,
            previous: previous,
            current: current
        )
        XCTAssertEqual(report.programsRenamed.count, 1)
        XCTAssertEqual(report.programsRenamed.first?.previousDisplayKey, "old-name|program")
        XCTAssertEqual(report.programsRenamed.first?.currentDisplayKey, "new-name|program")
        XCTAssertEqual(report.programsAdded, 0)
        XCTAssertEqual(report.programsRemoved, 0)
    }
}
