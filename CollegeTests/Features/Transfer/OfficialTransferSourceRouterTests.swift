// OfficialTransferSourceRouterTests.swift
// Feature: Transfer / Tests
// Purpose: Aggregator-first routing precedence tests.

import XCTest
@testable import College

final class OfficialTransferSourceRouterTests: XCTestCase {
    func testAggregatorRouteWhenASSISTSupported() {
        let manifest = SchoolManifest(
            id: "csu-test",
            name: "Test CSU",
            profileURL: "https://example.edu/profile",
            catalogFormat: "custom",
            lastUpdated: .now,
            coursesCount: 0,
            verified: true,
            transferAggregatorSupported: true,
            assistInstitutionID: "123"
        )
        let availability = TransferSourceAvailability.from(manifest: manifest)
        let routes = OfficialTransferSourceRouter.orderedRoutes(for: availability)
        XCTAssertEqual(routes.first, .aggregator)
    }

    func testTESRouteWhenOnlyPublicViewConfigured() {
        let manifest = SchoolManifest(
            id: "tes-test",
            name: "TES School",
            profileURL: "https://example.edu/profile",
            catalogFormat: "custom",
            lastUpdated: .now,
            coursesCount: 0,
            verified: true,
            transferAggregatorSupported: false,
            tesPublicViewURL: "https://tes.example.edu/publicview"
        )
        let availability = TransferSourceAvailability.from(manifest: manifest)
        let routes = OfficialTransferSourceRouter.orderedRoutes(for: availability)
        XCTAssertTrue(routes.contains(.tesPublicView))
    }

    func testFallbackAggregatorWhenNoManifestCapabilities() {
        let availability = TransferSourceAvailability.none
        XCTAssertEqual(OfficialTransferSourceRouter.orderedRoutes(for: availability), [.aggregator])
    }
}
