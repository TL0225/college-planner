// CatalogDocumentIRStoreTests.swift
// Feature: Shared
// Purpose: Round-trip persistence for CatalogDocumentIR JSON cache.
// Data: CollegePersistence / repositories when applicable.

import XCTest
@testable import College

final class CatalogDocumentIRStoreTests: XCTestCase {
    func testSaveAndLoad_roundTrip() {
        let schoolID = "test-ir-store-\(UUID().uuidString)"
        let versionID = "v1"
        let ir = CatalogPDFToDocumentIRAdapter.buildIR(
            schoolID: schoolID,
            catalogVersionID: versionID,
            sourceURL: "file:///test.pdf",
            classifiedBlocks: [],
            layoutProfileID: "pdf-test",
            layoutConfidence: 0.7
        )

        CatalogDocumentIRStore.save(ir, schoolID: schoolID, catalogVersionID: versionID)
        let loaded = CatalogDocumentIRStore.load(schoolID: schoolID, catalogVersionID: versionID)

        XCTAssertEqual(loaded, ir)
    }
}
