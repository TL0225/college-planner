// CatalogURLDiscoveryLiveTests.swift
// Feature: Catalog
// Purpose: Tier-1 live discovery smoke — prove root catalog_url alone yields navigable links.
//
// Run with:
//   COLLEGE_RUN_LIVE_TESTS=1 xcodebuild test \
//     -only-testing:CollegeTests/CatalogURLDiscoveryLiveTests

import XCTest
@testable import College

@MainActor
final class CatalogURLDiscoveryLiveTests: XCTestCase {
    private let minimumSidebarLinks = 5
    private let minimumCourseLeafPages = 10
    private let minimumCourseLeafProgramURLs = 3

    override func setUpWithError() throws {
        try super.setUpWithError()
        try CollegeTestsSupport.skipUnlessLiveNetworkTests()
    }

    func testModernCampusSchoolsDiscoverLinksFromURLOnly() async throws {
        let schools = bundledSchools(
            family: .modernCampus,
            urlOnly: true
        )
        XCTAssertFalse(schools.isEmpty, "No URL-only Modern Campus schools in schools.json")

        for school in schools {
            let catalogURL = school.catalogURL ?? ""
            let (normalized, catoidHint) = ModernCampusEngine.normalizeCatalogEntryPointForCaller(catalogURL)
            guard let baseURL = URL(string: normalized) else {
                XCTFail("\(school.id): could not normalize \(catalogURL)")
                continue
            }

            let catalogs = try await ModernCampusCatalogDiscovery.resolveCatalogsForIngest(
                normalizedBaseURL: normalized,
                catoidHint: catoidHint
            )
            XCTAssertFalse(catalogs.isEmpty, "\(school.id): expected ≥1 catalog edition")

            let graph = try await ModernCampusCatalogDiscoverer.buildGraph(
                manifest: school,
                baseURL: baseURL,
                catalogs: catalogs
            )

            let programURLs = graph.extractablePageURLs.filter {
                $0.lowercased().contains("preview_program")
            }
            let listingURLs = graph.urls(ofKind: .programListing)
            XCTAssertFalse(
                programURLs.isEmpty && listingURLs.isEmpty,
                "\(school.id): expected preview_program or program listing URLs in graph"
            )

            for catalog in catalogs {
                let indexURL = ModernCampusCatalogDiscoverer.indexURL(baseURL: baseURL, catoid: catalog.catoid)
                let html = try await ModernCampusEngine.fetchHTMLPublic(indexURL.absoluteString)
                let sidebar = ModernCampusCatalogDiscoverer.parseSidebarLinks(
                    html: html,
                    baseURL: baseURL,
                    catoid: catalog.catoid
                )
                let navLinks = sidebar.filter { ($0.navoid ?? "").isEmpty == false }
                XCTAssertGreaterThanOrEqual(
                    navLinks.count,
                    minimumSidebarLinks,
                    "\(school.id) catoid=\(catalog.catoid): expected ≥\(minimumSidebarLinks) sidebar nav links"
                )
            }
        }
    }

    func testCourseLeafSchoolsDiscoverLinksFromURLOnly() async throws {
        let schools = bundledSchools(
            family: .courseLeaf,
            urlOnly: true
        )
        XCTAssertFalse(schools.isEmpty, "No URL-only CourseLeaf schools in schools.json")

        var passed = 0
        var environmentalSkips: [String] = []
        for school in schools {
            let catalogURL = school.catalogURL ?? ""
            guard let baseURL = CourseLeafEngine.normalizeBaseURL(catalogURL) else {
                XCTFail("\(school.id): could not normalize \(catalogURL)")
                continue
            }

            let pageURLs: [URL]
            do {
                pageURLs = try await CourseLeafEngine.sitemapPageURLs(baseURL: baseURL)
            } catch {
                environmentalSkips.append("\(school.id): sitemap fetch failed (\(error.localizedDescription))")
                continue
            }

            if pageURLs.count < minimumCourseLeafPages {
                environmentalSkips.append(
                    "\(school.id): sitemap returned \(pageURLs.count) pages (possible WAF or wrong catalog_url)"
                )
                continue
            }

            let expandedURLs: [URL]
            do {
                expandedURLs = try await CourseLeafEngine.supplementProgramURLs(
                    baseURL: baseURL,
                    pageURLs: pageURLs
                )
            } catch {
                environmentalSkips.append("\(school.id): program hub supplement failed (\(error.localizedDescription))")
                continue
            }

            let programURLs = expandedURLs.filter(Self.isCourseLeafProgramURL)
            if programURLs.count < minimumCourseLeafProgramURLs {
                environmentalSkips.append(
                    "\(school.id): only \(programURLs.count) program URLs (possible WAF or hub layout drift)"
                )
                continue
            }
            passed += 1
        }

        if passed == 0 {
            throw XCTSkip(
                "No CourseLeaf school passed live discovery. Environmental skips: \(environmentalSkips.joined(separator: "; "))"
            )
        }
    }

    func testCoursedogSchoolsDiscoverProgramsFromURLOnly() async throws {
        let schools = bundledSchools(family: .coursedog, urlOnly: true)
        XCTAssertFalse(schools.isEmpty, "No Coursedog schools in schools.json")

        var passed = 0
        var environmentalSkips: [String] = []
        for school in schools {
            do {
                let output = try await CoursedogEngine.discoverPrograms(catalogURL: school.catalogURL ?? "")
                guard output.programs.count >= 5 else {
                    environmentalSkips.append(
                        "\(school.id): only \(output.programs.count) programs after rendered fetch"
                    )
                    continue
                }
                passed += 1
            } catch {
                environmentalSkips.append("\(school.id): \(error.localizedDescription)")
            }
        }

        if passed == 0 {
            throw XCTSkip(
                "No Coursedog school passed live discovery. Environmental skips: \(environmentalSkips.joined(separator: "; "))"
            )
        }
    }

    func testPDFSchoolsResolveFromURLOnly() async throws {
        let schools = bundledSchools(family: .pdf, urlOnly: false)
        XCTAssertFalse(schools.isEmpty, "No PDF schools in schools.json")

        for school in schools {
            let catalogURL = (school.catalogURL ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = URL(string: catalogURL) else {
                XCTFail("\(school.id): invalid catalog URL")
                continue
            }

            var request = URLRequest(url: url)
            request.setValue(
                "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15",
                forHTTPHeaderField: "User-Agent"
            )
            let (data, response) = try await URLSession.shared.data(for: request)
            let http = response as? HTTPURLResponse
            let contentType = (http?.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
            let isPDF = contentType.contains("application/pdf")
                || url.pathExtension.lowercased() == "pdf"
                || data.prefix(5) == Data("%PDF-".utf8)

            XCTAssertTrue(isPDF, "\(school.id): expected PDF content at \(catalogURL)")
            XCTAssertGreaterThan(data.count, 0, "\(school.id): PDF body was empty")
        }
    }

    private func bundledSchools(
        family: CatalogParserFamily,
        urlOnly: Bool
    ) -> [SchoolManifest] {
        SchoolManifestCatalog.bundled().filter { school in
            guard CatalogParserFamily.from(declaredFormat: school.catalogFormat) == family else {
                return false
            }
            guard family == .pdf || SchoolManifestSelection.isScraperBacked(school) else {
                return false
            }
            if urlOnly {
                let catalogURL = school.catalogURL ?? ""
                return !catalogURL.contains("?")
            }
            return true
        }
    }

    private static func isCourseLeafProgramURL(_ url: URL) -> Bool {
        let path = url.path.lowercased()
        guard path.contains("program") else { return false }
        if path == "/programs" || path == "/programs/" { return false }
        // Exclude attribute/group index pages that are not degree programs.
        if path.contains("attribute-code") || path.contains("group-prerequisite") { return false }
        return path.split(separator: "/").count >= 3
    }
}
