// CatalogLayoutDriftTests.swift
// Feature: Catalog
// Purpose: Layout fingerprint drift detection (non-blocking warnings).

import XCTest
@testable import College

final class CatalogLayoutDriftTests: XCTestCase {
    func testFingerprintDecode_defaultsToV1WhenMissingVersion() throws {
        let payload = """
        {
          "schoolID":"fordham_university",
          "catalogVersionID":"fordham|undergrad",
          "layoutProfileID":"profileB",
          "featureSignature":"abc",
          "recordedAt":"2026-07-01T00:00:00Z"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(CatalogLayoutFingerprint.self, from: Data(payload.utf8))
        XCTAssertEqual(decoded.signatureVersion, 1)
    }

    func testDrift_detectsProfileChange() {
        let previous = CatalogLayoutFingerprint(
            signatureVersion: 2,
            schoolID: "fordham_university",
            catalogVersionID: "fordham|undergrad",
            layoutProfileID: "profileB",
            featureSignature: "abc",
            recordedAt: Date()
        )
        let current = CatalogLayoutFingerprint(
            signatureVersion: 2,
            schoolID: "fordham_university",
            catalogVersionID: "fordham|undergrad",
            layoutProfileID: "profileDefault",
            featureSignature: "abc",
            recordedAt: Date()
        )
        let result = CatalogLayoutDriftDetector.evaluate(previous: previous, current: current)
        XCTAssertTrue(result.detected)
        XCTAssertTrue(result.message.contains("profile"))
    }

    func testRecordSuccessfulBaseline_enqueuesDriftWarning() {
        let schoolID = "tier2_drift_\(UUID().uuidString.prefix(8))"
        let versionID = "tier2|v1"
        #if DEBUG
        CatalogLayoutFingerprintStore.removeAll(forSchoolID: schoolID)
        #endif
        let outcomeA = CatalogIngestGate.evaluateCourseLeaf(
            manifest: driftTestManifest(schoolID: schoolID),
            depth: .light,
            programs: [driftTestProgram()],
            courses: [],
            requirements: [],
            layoutProfileID: "profileA"
        )
        XCTAssertEqual(outcomeA.recovery.outcome, .pass)
        CatalogIngestGate.recordSuccessfulBaseline(outcomeA)
        XCTAssertNotNil(
            CatalogLayoutFingerprintStore.load(schoolID: schoolID, catalogVersionID: outcomeA.metrics.catalogVersionID)
        )

        let secondMetrics = CatalogExtractorMetrics(
            schoolID: schoolID,
            catalogVersionID: outcomeA.metrics.catalogVersionID,
            source: "courseleaf",
            layoutProfileID: "profileC",
            programsFound: 100,
            coursesFound: 500,
            requirementsFound: 0,
            policiesFound: 0,
            requirementTablesFound: 0,
            averageEntityConfidence: nil,
            averageOwnershipConfidence: nil,
            recordedAt: Date()
        )
        let outcomeB = CatalogIngestGate.Outcome(
            metrics: secondMetrics,
            invariantResult: outcomeA.invariantResult,
            sanityResult: outcomeA.sanityResult,
            recovery: outcomeA.recovery,
            reviewSeverity: .informational,
            shouldAbortIngest: false,
            allowsRequirements: true
        )
        CatalogIngestGate.recordSuccessfulBaseline(outcomeB)
        let driftItems = CatalogReviewQueue.load().filter {
            $0.schoolID == schoolID && $0.reason.contains("catalog_layout_drift")
        }
        XCTAssertFalse(driftItems.isEmpty)
        XCTAssertEqual(driftItems.first?.severity, .warning)
    }

    private func driftTestManifest(schoolID: String) -> SchoolManifest {
        SchoolManifest(
            id: schoolID,
            name: "Drift Test",
            shortName: "Drift",
            unitID: nil,
            opeID: nil,
            profileURL: "https://example.edu/profile.json",
            catalogURL: "https://bulletin.example.edu/",
            academicCalendarURL: nil,
            timeZoneID: nil,
            countryCode: "US",
            stateCode: "NY",
            officialWebsiteURL: nil,
            financialAidURL: nil,
            registrarURL: nil,
            stateAidAgencyURL: nil,
            catalogFormat: "courseleaf",
            lastUpdated: Date(),
            coursesCount: 0,
            verified: false
        )
    }

    private func driftTestProgram() -> ScrapedProgram {
        ScrapedProgram(
            name: "Test Major",
            type: "Major",
            url: "https://bulletin.example.edu/undergraduate/test/",
            department: "TEST",
            college: nil,
            degreeType: "BS"
        )
    }
}
