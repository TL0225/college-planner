// CatalogPipelineEdgeCaseTests.swift
// Feature: Catalog
// Purpose: Edge-case coverage for ingest signatures, drift recovery, and manifest merge.

import XCTest
@testable import College

@MainActor
final class CatalogPipelineEdgeCaseTests: XCTestCase {
    override func tearDown() {
        UserDefaults.standard.removeObject(
            forKey: CatalogBackgroundSyncRunner.ingestSignatureKey(
                schoolID: "edge_case_school",
                format: "moderncampus",
                depth: .light
            )
        )
        super.tearDown()
    }

    func testModernCampusV2SignatureChangesWhenGraphChanges() {
        let base = CatalogIngestSignature.modernCampusV2(
            graphSourceSignature: "graph-a",
            layoutProfileID: "sidebarN2Links",
            programCount: 120
        )
        let changed = CatalogIngestSignature.modernCampusV2(
            graphSourceSignature: "graph-b",
            layoutProfileID: "sidebarN2Links",
            programCount: 120
        )
        XCTAssertTrue(CatalogIngestSignature.isV2(base))
        XCTAssertNotEqual(base, changed)
    }

    func testProgramCountBucketIsStableWithinBand() {
        XCTAssertEqual(CatalogIngestSignature.programCountBucket(49), CatalogIngestSignature.programCountBucket(1))
        XCTAssertNotEqual(CatalogIngestSignature.programCountBucket(49), CatalogIngestSignature.programCountBucket(50))
    }

    func testLayoutDriftClearsStoredIngestSignature() {
        let schoolID = "edge_case_school"
        let format = "moderncampus"
        CatalogBackgroundSyncRunner.setStoredIngestSignature(
            "v2:deadbeef",
            schoolID: schoolID,
            format: format,
            depth: .light
        )
        XCTAssertNotNil(
            CatalogBackgroundSyncRunner.storedIngestSignature(
                schoolID: schoolID,
                format: format,
                depth: .light
            )
        )

        let metrics = CatalogExtractorMetrics(
            schoolID: schoolID,
            catalogVersionID: "edge_case_school_1",
            source: format,
            layoutProfileID: "entityPreviewProgram",
            programsFound: 10,
            coursesFound: 0,
            requirementsFound: 0,
            policiesFound: 0,
            requirementTablesFound: 0,
            averageEntityConfidence: nil,
            averageOwnershipConfidence: nil,
            recordedAt: Date()
        )
        let previous = CatalogLayoutFingerprint(
            signatureVersion: 1,
            schoolID: schoolID,
            catalogVersionID: metrics.catalogVersionID,
            layoutProfileID: "sidebarN2Links",
            featureSignature: "feat-a",
            recordedAt: Date().addingTimeInterval(-3600)
        )
        let current = CatalogLayoutFingerprint.from(metrics: metrics)
        let drift = CatalogLayoutDriftDetector.evaluate(previous: previous, current: current)
        XCTAssertTrue(drift.detected)

        if drift.detected {
            CatalogBackgroundSyncRunner.clearStoredIngestSignatures(schoolID: schoolID, format: format)
        }
        XCTAssertNil(
            CatalogBackgroundSyncRunner.storedIngestSignature(
                schoolID: schoolID,
                format: format,
                depth: .light
            )
        )
    }

    func testModernCampusProfileRegistryResolvesUBEntityProfile() {
        let profile = ModernCampusProfileRegistry.resolvedProfileID(
            forSchoolID: "university_at_buffalo",
            host: "catalog.buffalo.edu",
            classifiedProfile: .sidebarN2Links
        )
        XCTAssertEqual(profile, .entityPreviewProgram)
    }
}
