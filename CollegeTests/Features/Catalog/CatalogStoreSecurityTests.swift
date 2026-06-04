// CatalogStoreSecurityTests.swift
// Feature: Catalog
// Purpose: Catalog module — CatalogStoreSecurityTests.
// Data: CollegePersistence / repositories when applicable.

import XCTest
@testable import College

final class CatalogStoreSecurityTests: XCTestCase {
    func testSignedStoreRoundTrip() throws {
        let sqliteData = Data("sqlite-fixture".utf8)
        let signed = try CatalogStoreSecurity.createSignedFile(
            schoolID: "fordham_university",
            sqliteData: sqliteData,
            storeSchemaVersion: "1.0"
        )

        let verified = try CatalogStoreSecurity.verifySignedFile(signed)
        XCTAssertEqual(verified.envelope.schoolID, "fordham_university")
        XCTAssertEqual(verified.sqliteData, sqliteData)
    }

    func testSignedStoreRejectsTamper() throws {
        let sqliteData = Data("sqlite-fixture".utf8)
        var signed = try CatalogStoreSecurity.createSignedFile(
            schoolID: "fordham_university",
            sqliteData: sqliteData,
            storeSchemaVersion: "1.0"
        )
        signed[signed.count - 1] ^= 0xFF

        XCTAssertThrowsError(try CatalogStoreSecurity.verifySignedFile(signed))
    }
}
