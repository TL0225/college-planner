// CatalogIngestSignatureTests.swift
// Feature: Catalog
// Purpose: Unit tests for ingest signature bucketing and v2 formatting.

import XCTest
@testable import College

final class CatalogIngestSignatureTests: XCTestCase {
    func testDiscoverySignatureIsDeterministic() {
        let catalogs = [
            ModernCampusCatalogDescriptor(catoid: "2", title: "Undergraduate"),
            ModernCampusCatalogDescriptor(catoid: "1", title: "Graduate"),
        ]
        let a = CatalogIngestSignature.discoveryFromCatalogs(catalogs)
        let b = CatalogIngestSignature.discoveryFromCatalogs(catalogs)
        XCTAssertEqual(a, b)
        XCTAssertFalse(CatalogIngestSignature.isV2(a))
    }

    func testV2PrefixAndLayoutSensitivity() {
        let sig = CatalogIngestSignature.modernCampusV2(
            graphSourceSignature: "abc",
            layoutProfileID: "sidebarN2Links",
            programCount: 75
        )
        XCTAssertTrue(sig.hasPrefix(CatalogIngestSignature.v2Prefix))
        let otherLayout = CatalogIngestSignature.modernCampusV2(
            graphSourceSignature: "abc",
            layoutProfileID: "entityPreviewProgram",
            programCount: 75
        )
        XCTAssertNotEqual(sig, otherLayout)
    }
}
