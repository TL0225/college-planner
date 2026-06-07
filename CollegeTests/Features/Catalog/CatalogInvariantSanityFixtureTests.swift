// CatalogInvariantSanityFixtureTests.swift
// Feature: Shared
// Purpose: Ingest gate critical vs warning behavior on fixture-scale metrics.
// Data: CollegePersistence / repositories when applicable.

import XCTest
@testable import College

final class CatalogInvariantSanityFixtureTests: XCTestCase {
    private func makeManifest() -> SchoolManifest {
        SchoolManifest(
            id: "fordham_university",
            name: "Fordham",
            shortName: "Fordham",
            unitID: nil,
            opeID: nil,
            profileURL: "https://example.edu/profile.json",
            catalogURL: "https://bulletin.fordham.edu/",
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

    func testIngestGate_criticalWhenNoPrograms() {
        let outcome = CatalogIngestGate.evaluateCourseLeaf(
            manifest: makeManifest(),
            depth: .light,
            programs: [],
            courses: [],
            requirements: [],
            layoutProfileID: "profileB"
        )
        XCTAssertEqual(outcome.reviewSeverity, .critical)
        XCTAssertTrue(outcome.shouldAbortIngest)
    }

    func testIngestGate_warningNotBlockingWithProgramsOnly() {
        let program = ScrapedProgram(
            name: "African American Studies",
            type: "Major",
            url: "https://bulletin.fordham.edu/undergraduate/african-american-studies/",
            department: "AAST",
            college: nil,
            degreeType: "BA"
        )
        let outcome = CatalogIngestGate.evaluateCourseLeaf(
            manifest: makeManifest(),
            depth: .light,
            programs: [program],
            courses: [],
            requirements: [],
            layoutProfileID: "profileB",
            averageEntityConfidence: 0.82
        )
        XCTAssertFalse(outcome.shouldAbortIngest)
        XCTAssertNotEqual(outcome.reviewSeverity, .critical)
    }
}
