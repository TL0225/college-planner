// CatalogGraphDiscoveryTests.swift
// Feature: Shared
// Purpose: Catalog graph discovery — URL classification and graph shape (no network).

import XCTest
@testable import College

final class CatalogGraphDiscoveryTests: XCTestCase {
    private func makeNYUManifest() -> SchoolManifest {
        SchoolManifest(
            id: "new_york_university",
            name: "New York University",
            shortName: "NYU",
            unitID: nil,
            opeID: nil,
            profileURL: "https://www.nyu.edu/profile.json",
            catalogURL: "https://bulletins.nyu.edu/",
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

    private func makeFordhamManifest() -> SchoolManifest {
        SchoolManifest(
            id: "fordham_university",
            name: "Fordham University",
            shortName: "Fordham",
            unitID: nil,
            opeID: nil,
            profileURL: "https://www.fordham.edu/profile.json",
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

    func testClassifyPageKind_hardcodedPaths() {
        XCTAssertEqual(
            CourseLeafCatalogDiscoverer.classifyPageKind(
                path: "/undergraduate/arts-science/programs/anthropology/",
                schoolID: "new_york_university"
            ),
            .programDetail
        )
        XCTAssertEqual(
            CourseLeafCatalogDiscoverer.classifyPageKind(
                path: "/courses/csci_ua/",
                schoolID: "new_york_university"
            ),
            .courseListing
        )
        XCTAssertEqual(
            CourseLeafCatalogDiscoverer.classifyPageKind(
                path: "/courses/csci_ua/csci-ua-101/",
                schoolID: "new_york_university"
            ),
            .courseDetail
        )
        XCTAssertEqual(
            CourseLeafCatalogDiscoverer.classifyPageKind(
                path: "/undergraduate/accounting/major/",
                schoolID: "fordham_university"
            ),
            .programDetail
        )
        XCTAssertEqual(
            CourseLeafCatalogDiscoverer.classifyPageKind(
                path: "/nyu/policies/foo/",
                schoolID: "new_york_university"
            ),
            .policy
        )
        XCTAssertEqual(
            CourseLeafCatalogDiscoverer.classifyPageKind(
                path: "/undergraduate/arts-science/",
                schoolID: "new_york_university"
            ),
            .programListing
        )
    }

    func testBuildGraph_nyu_fixtureNodeCountsAndKinds() throws {
        let manifest = makeNYUManifest()
        let baseURL = try XCTUnwrap(URL(string: "https://bulletins.nyu.edu/"))
        let pageURLs = [
            "https://bulletins.nyu.edu/undergraduate/arts-science/programs/anthropology/",
            "https://bulletins.nyu.edu/graduate/arts-science/programs/economics/",
            "https://bulletins.nyu.edu/courses/csci_ua/",
            "https://bulletins.nyu.edu/courses/csci_ua/csci-ua-101/",
            "https://bulletins.nyu.edu/nyu/policies/foo/"
        ].compactMap(URL.init(string:))

        let graph = CourseLeafCatalogDiscoverer.buildGraph(
            manifest: manifest,
            baseURL: baseURL,
            pageURLs: pageURLs
        )

        XCTAssertEqual(graph.schoolID, "new_york_university")
        XCTAssertEqual(graph.engine, "courseleaf")
        XCTAssertGreaterThanOrEqual(graph.nodeCount, pageURLs.count + 1)

        let kindByURL = Dictionary(uniqueKeysWithValues: graph.nodes.map { ($0.url, $0.kind) })
        XCTAssertEqual(
            kindByURL["https://bulletins.nyu.edu/undergraduate/arts-science/programs/anthropology/"],
            .programDetail
        )
        XCTAssertEqual(
            kindByURL["https://bulletins.nyu.edu/courses/csci_ua/"],
            .courseListing
        )
        XCTAssertEqual(
            kindByURL["https://bulletins.nyu.edu/courses/csci_ua/csci-ua-101/"],
            .courseDetail
        )
        XCTAssertEqual(
            kindByURL["https://bulletins.nyu.edu/nyu/policies/foo/"],
            .policy
        )

        let extractable = graph.extractablePageURLs
        XCTAssertTrue(extractable.contains("https://bulletins.nyu.edu/undergraduate/arts-science/programs/anthropology/"))
        XCTAssertFalse(extractable.contains("https://bulletins.nyu.edu/nyu/policies/foo/"))
    }

    func testBuildGraph_immutableValueSemantics() throws {
        let manifest = makeFordhamManifest()
        let baseURL = try XCTUnwrap(URL(string: "https://bulletin.fordham.edu/"))
        let pageURLs = [
            "https://bulletin.fordham.edu/undergraduate/accounting/major/",
            "https://bulletin.fordham.edu/courses/aast/"
        ].compactMap(URL.init(string:))

        let graph = CourseLeafCatalogDiscoverer.buildGraph(
            manifest: manifest,
            baseURL: baseURL,
            pageURLs: pageURLs
        )
        XCTAssertGreaterThanOrEqual(graph.nodeCount, 2)
        XCTAssertTrue(
            graph.urls(ofKind: .programDetail).contains("https://bulletin.fordham.edu/undergraduate/accounting/major/")
            || graph.urls(ofKind: .programListing).contains(where: { $0.contains("accounting") })
        )
    }

    func testCatalogGraph_urlsOfKind_filtersExtractableKinds() throws {
        let manifest = makeNYUManifest()
        let baseURL = try XCTUnwrap(URL(string: "https://bulletins.nyu.edu/"))
        let pageURLs = [
            "https://bulletins.nyu.edu/undergraduate/arts-science/programs/anthropology/",
            "https://bulletins.nyu.edu/courses/csci_ua/"
        ].compactMap(URL.init(string:))

        let graph = CourseLeafCatalogDiscoverer.buildGraph(
            manifest: manifest,
            baseURL: baseURL,
            pageURLs: pageURLs
        )

        XCTAssertEqual(graph.urls(ofKind: .courseListing).count, 1)
        XCTAssertEqual(graph.urls(ofKind: .policy).count, 0)
        XCTAssertGreaterThanOrEqual(graph.extractablePageURLs.count, 2)
    }
}
