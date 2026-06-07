// CatalogManifestCapabilitiesTests.swift
// Feature: Shared
// Purpose: Per-school capability metadata beyond engine defaults.

import XCTest
@testable import College

final class CatalogManifestCapabilitiesTests: XCTestCase {
    func testCapabilityStore_roundTrip() {
        let schoolID = "caps_fixture_\(UUID().uuidString)"
        let caps = CatalogManifestCapabilities(
            supportsTransferEquivalencies: true,
            supportsArticulationIngest: false
        )
        CatalogManifestCapabilityStore.save(caps, schoolID: schoolID)
        let loaded = CatalogManifestCapabilityStore.capabilities(forSchoolID: schoolID, format: "courseleaf")
        XCTAssertEqual(loaded, caps)
    }

    func testEngineCapabilities_includeTransferFlags() {
        let caps = CatalogEngineCapabilityDefaults.shared.capabilities(for: .modernCampus)
        XCTAssertFalse(caps.supportsTransferEquivalencies)
        XCTAssertFalse(caps.supportsArticulationIngest)
    }
}
