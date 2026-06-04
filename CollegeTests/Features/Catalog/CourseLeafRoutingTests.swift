// CourseLeafRoutingTests.swift
// Feature: Shared
// Purpose: Shared module — CourseLeafRoutingTests.
// Data: CollegePersistence / repositories when applicable.

import XCTest
@testable import College

final class CourseLeafRoutingTests: XCTestCase {
    func testScraperBackedSelectionIncludesCourseLeaf() {
        let manifest = makeManifest(format: "courseleaf", url: "https://bulletin.fordham.edu/")
        XCTAssertTrue(SchoolManifestSelection.isScraperBacked(manifest))
    }

    func testScraperBackedSelectionExcludesPDF() {
        let manifest = makeManifest(format: "pdf", url: "https://example.edu/catalog.pdf")
        XCTAssertFalse(SchoolManifestSelection.isScraperBacked(manifest))
    }

    func testCatalogIngestEngineNormalization() {
        XCTAssertEqual(CatalogIngestEngine(manifestFormat: "acalog"), .modernCampus)
        XCTAssertEqual(CatalogIngestEngine(manifestFormat: "moderncampus"), .modernCampus)
        XCTAssertEqual(CatalogIngestEngine(manifestFormat: "courseleaf"), .courseLeaf)
        XCTAssertEqual(CatalogIngestEngine(manifestFormat: "pdf"), .pdf)
        XCTAssertEqual(CatalogIngestEngine(manifestFormat: "something-else"), .unknown)
    }

    func testLiveIngestCoordinatorFormatSupport() {
        XCTAssertTrue(CatalogBackgroundSyncRunner.supportsLiveIngestCoordinator(format: "acalog"))
        XCTAssertTrue(CatalogBackgroundSyncRunner.supportsLiveIngestCoordinator(format: "moderncampus"))
        XCTAssertTrue(CatalogBackgroundSyncRunner.supportsLiveIngestCoordinator(format: "courseleaf"))
        XCTAssertFalse(CatalogBackgroundSyncRunner.supportsLiveIngestCoordinator(format: "pdf"))
        XCTAssertFalse(CatalogBackgroundSyncRunner.supportsLiveIngestCoordinator(format: "banner"))
    }

    func testBundledSchoolManifestsIncludeNewYorkUniversityForOnboardingPicker() {
        let names = SchoolManifestSelection.scraperBackedNames(from: SchoolManifestCatalog.bundled())
        XCTAssertTrue(
            names.contains { $0.caseInsensitiveCompare("New York University") == .orderedSame },
            "Bundled schools.json must include NYU for the onboarding school picker."
        )

        let nyu = SchoolManifestCatalog.bundled().first { $0.id == "new_york_university" }
        XCTAssertEqual(nyu?.catalogFormat.lowercased(), "courseleaf")
        XCTAssertEqual(nyu?.catalogURL, "https://bulletins.nyu.edu/")
    }

    private func makeManifest(format: String, url: String) -> SchoolManifest {
        SchoolManifest(
            id: "test_school",
            name: "Test School",
            shortName: "Test",
            unitID: nil,
            opeID: nil,
            profileURL: "https://example.edu/profile.json",
            catalogURL: url,
            countryCode: nil,
            stateCode: nil,
            officialWebsiteURL: nil,
            financialAidURL: nil,
            registrarURL: nil,
            stateAidAgencyURL: nil,
            catalogFormat: format,
            lastUpdated: Date(),
            coursesCount: 0,
            verified: false
        )
    }
}
