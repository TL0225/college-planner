// UniversalCatalogScraperIRConsumerTests.swift
// Feature: Shared
// Purpose: Document IR merge/build helpers for UniversalCatalogScraper graph consumer.

import XCTest
@testable import College

final class UniversalCatalogScraperIRConsumerTests: XCTestCase {
    func testMergeNodes_deduplicatesBySignature() {
        let nodeA = CatalogDocumentNode(
            depth: 0,
            kind: .heading,
            text: "Majors",
            elementSignature: "sig-a"
        )
        let nodeADup = CatalogDocumentNode(
            depth: 0,
            kind: .heading,
            text: "Majors",
            elementSignature: "sig-a"
        )
        let nodeB = CatalogDocumentNode(
            depth: 1,
            kind: .linkList,
            text: "Programs",
            elementSignature: "sig-b"
        )
        var merged: [CatalogDocumentNode] = [nodeA]
        UniversalCatalogScraperIRConsumer.mergeNodes([nodeADup, nodeB], into: &merged)
        XCTAssertEqual(merged.count, 2)
    }

    func testBuildDocumentIR_fromNodes() {
        let node = CatalogDocumentNode(depth: 0, kind: .section, text: "Catalog", elementSignature: "section-1")
        let ir = UniversalCatalogScraperIRConsumer.buildDocumentIR(
            schoolID: "fixture_school",
            catalogVersionID: "fixture_version",
            nodes: [node],
            layoutProfileID: "universal-scraper"
        )
        XCTAssertNotNil(ir)
        XCTAssertEqual(ir?.nodes.count, 1)
        XCTAssertEqual(ir?.layoutProfileID, "universal-scraper")
    }
}
