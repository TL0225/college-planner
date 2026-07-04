// ModernCampusCatalogDiscovererTests.swift
// Feature: Shared
// Purpose: Modern Campus graph discovery — URL classification and offline graph shape.

import XCTest
@testable import College

final class ModernCampusCatalogDiscovererTests: XCTestCase {
    private func makeUBManifest() -> SchoolManifest {
        SchoolManifest(
            id: "university_at_buffalo",
            name: "University at Buffalo",
            shortName: "UB",
            unitID: "196088",
            opeID: "00283700",
            profileURL: "https://www.buffalo.edu/profile.json",
            catalogURL: "https://catalogs.buffalo.edu/",
            academicCalendarURL: nil,
            timeZoneID: nil,
            countryCode: "US",
            stateCode: "NY",
            officialWebsiteURL: "https://www.buffalo.edu/",
            financialAidURL: nil,
            registrarURL: nil,
            stateAidAgencyURL: nil,
            catalogFormat: "moderncampus",
            lastUpdated: Date(),
            coursesCount: 0,
            verified: false
        )
    }

    func testClassifyPageKind_hardcodedURLs() {
        XCTAssertEqual(
            ModernCampusCatalogDiscoverer.classifyPageKind(
                url: "https://catalogs.buffalo.edu/index.php?catoid=17"
            ),
            .index
        )
        XCTAssertEqual(
            ModernCampusCatalogDiscoverer.classifyPageKind(
                url: "https://catalogs.buffalo.edu/content.php?catoid=17&navoid=862",
                linkLabel: "Courses"
            ),
            .courseListing
        )
        XCTAssertEqual(
            ModernCampusCatalogDiscoverer.classifyPageKind(
                url: "https://catalogs.buffalo.edu/preview_program.php?catoid=17&poid=1234"
            ),
            .programDetail
        )
        XCTAssertEqual(
            ModernCampusCatalogDiscoverer.classifyPageKind(
                url: "https://catalogs.buffalo.edu/preview_course_nopop.php?catoid=17&coid=99"
            ),
            .courseDetail
        )
        XCTAssertEqual(
            ModernCampusCatalogDiscoverer.classifyPageKind(
                url: "https://catalogs.buffalo.edu/content.php?catoid=17&navoid=500",
                linkLabel: "Majors"
            ),
            .programListing
        )
        XCTAssertEqual(
            ModernCampusCatalogDiscoverer.classifyPageKind(
                url: "https://catalogs.buffalo.edu/content.php?catoid=17&navoid=900",
                linkLabel: "Academic Regulations"
            ),
            .policy
        )
    }

    func testParseSidebarLinks_fromSnippet() {
        let html = """
        <table class="block_n2_links link_table">
          <tr><td><div class="n2_links"><a href="content.php?catoid=17&amp;navoid=862">Courses</a></div></td></tr>
          <tr><td><div class="n2_links"><a href="content.php?catoid=17&amp;navoid=1040">Majors</a></div></td></tr>
        </table>
        """
        let base = URL(string: "https://catalogs.buffalo.edu/")!
        let links = ModernCampusCatalogDiscoverer.parseSidebarLinks(html: html, baseURL: base, catoid: "17")
        XCTAssertEqual(links.count, 2)
        XCTAssertEqual(links[0].label, "Courses")
        XCTAssertTrue(links[0].url.contains("navoid=862"))
        XCTAssertEqual(links[1].label, "Majors")
    }

    func testBuildGraph_offlineNodeKinds() throws {
        let manifest = makeUBManifest()
        let base = try XCTUnwrap(URL(string: "https://catalogs.buffalo.edu/"))
        let catalogs = [ModernCampusCatalogDescriptor(catoid: "17", title: "Undergraduate")]
        let sidebar: [String: [ModernCampusCatalogDiscoverer.SidebarEntry]] = [
            "17": [
                .init(
                    label: "Courses",
                    url: "https://catalogs.buffalo.edu/content.php?catoid=17&navoid=862",
                    navoid: "862"
                ),
                .init(
                    label: "Majors",
                    url: "https://catalogs.buffalo.edu/content.php?catoid=17&navoid=1040",
                    navoid: "1040"
                )
            ]
        ]
        let extra = [
            "https://catalogs.buffalo.edu/preview_program.php?catoid=17&poid=1"
        ]

        let graph = ModernCampusCatalogDiscoverer.buildGraph(
            manifest: manifest,
            baseURL: base,
            catalogs: catalogs,
            pageURLs: extra,
            sidebarByCatoid: sidebar
        )

        XCTAssertEqual(graph.engine, "moderncampus")
        XCTAssertEqual(graph.schoolID, "university_at_buffalo")
        XCTAssertGreaterThanOrEqual(graph.nodeCount, 4)

        let kindByURL = Dictionary(uniqueKeysWithValues: graph.nodes.map { ($0.url, $0.kind) })
        XCTAssertEqual(
            kindByURL["https://catalogs.buffalo.edu/index.php?catoid=17"],
            .index
        )
        XCTAssertEqual(
            kindByURL["https://catalogs.buffalo.edu/content.php?catoid=17&navoid=862"],
            .courseListing
        )
        XCTAssertEqual(
            kindByURL["https://catalogs.buffalo.edu/content.php?catoid=17&navoid=1040"],
            .programListing
        )
        XCTAssertEqual(
            kindByURL["https://catalogs.buffalo.edu/preview_program.php?catoid=17&poid=1"],
            .programDetail
        )
    }

    func testResolve_buffaloHostEnablesEntityDiscovery() {
        XCTAssertTrue(ModernCampusHostProfiles.resolve(host: "catalogs.buffalo.edu")?.prefersEntityPageProgramDiscovery == true)
        let generic = ModernCampusProfileConfig.forHost("catalog.example.edu")
        XCTAssertFalse(generic.prefersEntityPageProgramDiscovery)
    }

    func testNavLabelSynonyms_includesGlobalDefaultsForUnknownHost() {
        let synonyms = ModernCampusHostProfiles.navLabelSynonyms(host: "catalog.dsu.edu")
        XCTAssertTrue(synonyms.contains(where: { $0.contains("programs of study") }))
    }

    func testReclassifyUnknown_promotesHighProgramLinkDensity() {
        let html = """
        <a href="preview_program.php?poid=1">A</a>
        <a href="preview_program.php?poid=2">B</a>
        <a href="preview_entity.php?entoid=1">C</a>
        """
        let kind = ModernCampusCatalogDiscoverer.reclassifyUnknownPageKind(
            url: "https://catalog.dsu.edu/content.php?catoid=7&navoid=500",
            linkLabel: "Departments",
            host: "catalog.dsu.edu",
            listingHTML: html
        )
        XCTAssertEqual(kind, .programListing)
    }
}
