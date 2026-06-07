// CatalogSchoolDataPurgeTests.swift
// Feature: Catalog
// Purpose: Catalog module — CatalogSchoolDataPurgeTests.
// Data: CollegePersistence / repositories when applicable.

import XCTest
@testable import College

final class CatalogSchoolDataPurgeTests: XCTestCase {
    func testProgramURLNeedle_nyuUsesBulletinsHost() {
        XCTAssertEqual(
            CatalogSchoolDataPurge.programURLNeedle(forSchoolID: "new_york_university", catalogURL: nil),
            "bulletins.nyu"
        )
    }

    func testSelectedProgramStore_pruneKeepsOtherUniversities() {
        let nyuID = "New York University | undergraduate | Computer Science (BA)"
        let fordhamID = "Fordham University | undergraduate | Economics (BA)"
        CatalogSelectedProgramsStore.replace([nyuID, fordhamID])
        defer { CatalogSelectedProgramsStore.clear() }

        let prefix = "New York University |"
        let remaining = CatalogSelectedProgramsStore.allSelected().filter { !$0.hasPrefix(prefix) }
        CatalogSelectedProgramsStore.replace(remaining)

        XCTAssertEqual(CatalogSelectedProgramsStore.allSelected(), [fordhamID])
    }
}
