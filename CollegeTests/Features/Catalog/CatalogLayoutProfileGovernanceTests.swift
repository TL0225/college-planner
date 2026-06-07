// CatalogLayoutProfileGovernanceTests.swift
// Feature: Shared
// Purpose: Layout profile governance and school override resolution.

import XCTest
@testable import College

final class CatalogLayoutProfileGovernanceTests: XCTestCase {
    func testMinSchoolsForNewProfile() {
        XCTAssertEqual(CatalogLayoutProfileGovernance.minSchoolsForNewProfile, 5)
        XCTAssertFalse(CatalogLayoutProfileGovernance.canAdoptNewProfile(assigningSchoolIDs: ["a", "b"]))
        XCTAssertTrue(
            CatalogLayoutProfileGovernance.canAdoptNewProfile(
                assigningSchoolIDs: ["a", "b", "c", "d", "e"]
            )
        )
    }

    func testResolvedProfileID_prefersOverride() {
        let schoolID = "test_school_override_\(UUID().uuidString)"
        SchoolLayoutOverrideStore.save(
            SchoolLayoutOverride(schoolID: schoolID, profileID: "profileB", reason: "fixture")
        )
        let resolved = CatalogLayoutProfileRegistry.resolvedProfileID(
            forSchoolID: schoolID,
            classifiedProfile: .profileDefault
        )
        XCTAssertEqual(resolved, .profileB)
    }

    func testValidateRegistryAdoption_rejectsSparseProfile() {
        let entry = CatalogLayoutProfileEntry(
            id: "profileX",
            label: "Sparse",
            schoolIDs: ["only_one"],
            domSignals: []
        )
        XCTAssertNotNil(CatalogLayoutProfileRegistry.validateRegistryAdoption(entry))
    }
}
