// DakotaStateUniversityCatalogScraperTests.swift
// Feature: Shared
// Purpose: Shared module — DakotaStateUniversityCatalogScraperTests.
// Data: CollegePersistence / repositories when applicable.

import XCTest
@testable import College

/// Live network checks for Dakota State University (`catalog.dsu.edu`).
final class DakotaStateUniversityCatalogScraperTests: XCTestCase {
    private let catalogURL = "https://catalog.dsu.edu/"

    func testBundledSchoolManifestIncludesDakotaStateUniversity() {
        let bundled = SchoolManifestCatalog.bundled()
        XCTAssertGreaterThanOrEqual(bundled.count, 4, "Bundled schools.json should list all supported schools")

        let dsu = bundled.first { $0.id == "dakota_state_university" }
        XCTAssertNotNil(dsu)
        XCTAssertEqual(dsu?.name, "Dakota State University")
        XCTAssertEqual(dsu?.catalogFormat.lowercased(), "acalog")
        XCTAssertEqual(dsu?.catalogURL, catalogURL)

        let ids = Set(bundled.map(\.id))
        XCTAssertTrue(ids.contains("rutgers_nb"))
        XCTAssertTrue(ids.contains("stony_brook"))
        XCTAssertTrue(ids.contains("university_at_buffalo"))
    }

    func testDiscoverActiveCatalogs_findsUndergraduateAndGraduate() async throws {
        try CollegeTestsSupport.skipUnlessLiveNetworkTests()
        let (normalized, _) = ModernCampusEngine.normalizeCatalogEntryPointForCaller(catalogURL)
        let discovered = try await ModernCampusEngine.discoverActiveCatalogs(baseURL: normalized)
        let reduced = ModernCampusCatalogLabels.latestCatalogsPerNormalizedLabel(from: discovered)

        let labels = Set(reduced.map { ModernCampusCatalogLabels.normalizedCatalogTypeLabel(from: $0.title, catoid: $0.catoid) })
        XCTAssertTrue(labels.contains("Undergraduate"), "Expected current undergraduate catalog, got: \(reduced)")
        XCTAssertTrue(labels.contains("Graduate"), "Expected current graduate catalog, got: \(reduced)")
    }

    func testScrapePrograms_topologyOnly_returnsPrograms() async throws {
        try CollegeTestsSupport.skipUnlessLiveNetworkTests()
        let (normalized, _) = ModernCampusEngine.normalizeCatalogEntryPointForCaller(catalogURL)
        guard let baseURL = URL(string: normalized) else {
            XCTFail("Invalid normalized catalog URL")
            return
        }

        let discovered = try await ModernCampusEngine.discoverActiveCatalogs(baseURL: normalized)
        let reduced = ModernCampusCatalogLabels.latestCatalogsPerNormalizedLabel(from: discovered)
        let undergrad = reduced.first {
            ModernCampusCatalogLabels.normalizedCatalogTypeLabel(from: $0.title, catoid: $0.catoid) == "Undergraduate"
        }
        XCTAssertNotNil(undergrad)

        let catalogID = Int(undergrad!.catoid) ?? 0
        XCTAssertGreaterThan(catalogID, 0)

        let scraper = UniversalCatalogScraper()
        let programs = try await scraper.scrapeAllPrograms(
            baseURL: baseURL,
            catalogID: catalogID,
            programsIndexOnly: true
        )
        XCTAssertGreaterThan(programs.count, 5, "Expected multiple undergraduate programs from DSU catalog")
    }
}
