// ModernCampusCatalogLabelsTests.swift
// Purpose: Catalog list deduplication for multi-edition schools (e.g. UB).

import SwiftSoup
import XCTest
@testable import College

final class ModernCampusCatalogLabelsTests: XCTestCase {
    func testLatestCatalogsPerNormalizedLabel_collapsesYearEditions() {
        // UB-style list: multiple year editions per school catalog type.
        let posted: [ModernCampusCatalogDescriptor] = [
            ModernCampusCatalogDescriptor(catoid: "10", title: "2023-2024 Undergraduate Catalog"),
            ModernCampusCatalogDescriptor(catoid: "17", title: "2025-2026 Undergraduate Catalog"),
            ModernCampusCatalogDescriptor(catoid: "11", title: "2023-2024 Graduate Catalog"),
            ModernCampusCatalogDescriptor(catoid: "18", title: "2025-2026 Graduate Catalog"),
            ModernCampusCatalogDescriptor(catoid: "12", title: "2023-2024 Law School Catalog"),
            ModernCampusCatalogDescriptor(catoid: "19", title: "2025-2026 Law School Catalog"),
            ModernCampusCatalogDescriptor(catoid: "13", title: "2023-2024 Dental School Catalog"),
            ModernCampusCatalogDescriptor(catoid: "20", title: "2025-2026 Dental School Catalog"),
            ModernCampusCatalogDescriptor(catoid: "14", title: "2023-2024 JSMBS Medical School Catalog"),
            ModernCampusCatalogDescriptor(catoid: "21", title: "2025-2026 JSMBS Medical School Catalog"),
        ]

        let reduced = ModernCampusCatalogLabels.latestCatalogsPerNormalizedLabel(from: posted)

        XCTAssertEqual(reduced.count, 5)
        let labels = Set(reduced.map {
            ModernCampusCatalogLabels.normalizedCatalogTypeLabel(from: $0.title, catoid: $0.catoid)
        })
        XCTAssertEqual(labels, Set(["Undergraduate", "Graduate", "Law School", "Dental School", "JSMBS Medical School"]))
        XCTAssertTrue(reduced.allSatisfy { $0.title.contains("2025-2026") })
    }

    func testFilterPostedCatalogs_excludesArchivedAndHomeRows() {
        let rows: [ModernCampusCatalogDescriptor] = [
            ModernCampusCatalogDescriptor(catoid: "1", title: "Catalog Home"),
            ModernCampusCatalogDescriptor(catoid: "2", title: "2024-2025 Undergraduate Catalog (Archived)"),
            ModernCampusCatalogDescriptor(catoid: "17", title: "2025-2026 Undergraduate Catalog"),
        ]

        let posted = ModernCampusCatalogLabels.filterPostedCatalogs(from: rows)
        XCTAssertEqual(posted.count, 1)
        XCTAssertEqual(posted[0].catoid, "17")
    }

    func testIsArchivedCatalogListTitle_matchesCaseInsensitiveMarkers() {
        XCTAssertTrue(ModernCampusCatalogLabels.isArchivedCatalogListTitle("2025-2026 Undergraduate Catalog [ARCHIVED CATALOG]"))
        XCTAssertTrue(ModernCampusCatalogLabels.isArchivedCatalogListTitle("2024-2025 Graduate Catalog (archived)"))
        XCTAssertFalse(ModernCampusCatalogLabels.isArchivedCatalogListTitle("2026-2027 Undergraduate Catalog"))
    }

    func testParseCatalogListPage_excludesUBArchivedTrailingMarker() throws {
        let html = """
        <p>
        <a href='/index.php?catoid=21'>2026-2027 Undergraduate Catalog</a><br/>
        <a href='/index.php?catoid=19'>2025-2026 Graduate Catalog</a><br/>
        <a href='/index.php?catoid=17'>2025-2026 Undergraduate Catalog</a> [ARCHIVED CATALOG]<br/>
        <a href='/index.php?catoid=11'>2024-2025 Undergraduate Catalog</a> [ARCHIVED CATALOG]<br/>
        </p>
        """
        let doc = try SwiftSoup.parse(html)
        let catalogs = ModernCampusEngine.parseCatalogListPage(doc: doc, host: "catalogs.buffalo.edu")

        XCTAssertEqual(catalogs.count, 2)
        XCTAssertEqual(Set(catalogs.map(\.catoid)), Set(["21", "19"]))
        XCTAssertTrue(catalogs.allSatisfy { !ModernCampusCatalogLabels.isArchivedCatalogListTitle($0.title) })
    }
}
