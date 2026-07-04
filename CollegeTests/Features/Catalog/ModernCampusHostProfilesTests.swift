// ModernCampusHostProfilesTests.swift
// Feature: Catalog
// Purpose: Host profile registry behaviors for Modern Campus.

import XCTest
@testable import College

final class ModernCampusHostProfilesTests: XCTestCase {
    func testResolve_buffaloHostEnablesEntityDiscovery() {
        let profile = ModernCampusHostProfiles.resolve(host: "catalogs.buffalo.edu")
        XCTAssertEqual(profile?.id, "ub")
        XCTAssertEqual(profile?.prefersEntityPageProgramDiscovery, true)
    }

    func testNavLabelSynonyms_returnsUBVariants() {
        let labels = ModernCampusHostProfiles.navLabelSynonyms(host: "catalog.buffalo.edu")
        XCTAssertTrue(labels.contains("departments & programs"))
        XCTAssertTrue(labels.contains("academic programs"))
    }
}
