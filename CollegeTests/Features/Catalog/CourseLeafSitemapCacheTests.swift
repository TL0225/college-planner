// CourseLeafSitemapCacheTests.swift
// Feature: Catalog
// Purpose: CourseLeaf sitemap cache deduplicates network fetches per base URL.

import XCTest
@testable import College

private final class FetchCounter: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var count = 0

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }
}

final class CourseLeafSitemapCacheTests: XCTestCase {
    override func tearDown() async throws {
        await CourseLeafSitemapCache.resetFetchXMLForTesting()
        await CourseLeafSitemapCache.clear()
        try await super.tearDown()
    }

    func testPageURLs_cacheHitAvoidsSecondFetch() async throws {
        let base = URL(string: "https://bulletins.nyu.edu/")!
        let fetchCounter = FetchCounter()
        let fixture = """
        <?xml version="1.0"?>
        <urlset>
          <url><loc>https://bulletins.nyu.edu/undergraduate/foo/</loc></url>
          <url><loc>https://bulletins.nyu.edu/courses/bar/</loc></url>
        </urlset>
        """

        await CourseLeafSitemapCache.clear()
        await CourseLeafSitemapCache.setFetchXMLForTesting { url in
            fetchCounter.increment()
            XCTAssertTrue(url.absoluteString.hasSuffix("sitemap.xml"))
            return fixture
        }

        let first = try await CourseLeafSitemapCache.pageURLs(baseURL: base)
        let second = try await CourseLeafSitemapCache.pageURLs(baseURL: base)

        XCTAssertEqual(fetchCounter.count, 1)
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.count, 2)
    }

    func testCacheKey_normalizesTrailingSlash() {
        let withSlash = URL(string: "https://bulletins.nyu.edu/")!
        let withoutSlash = URL(string: "https://bulletins.nyu.edu")!
        XCTAssertEqual(
            CourseLeafSitemapCache.cacheKey(for: withSlash),
            CourseLeafSitemapCache.cacheKey(for: withoutSlash)
        )
    }

    func testClear_forcesRefetch() async throws {
        let base = URL(string: "https://bulletin.fordham.edu/")!
        let fetchCounter = FetchCounter()

        await CourseLeafSitemapCache.setFetchXMLForTesting { _ in
            fetchCounter.increment()
            return "<urlset><url><loc>https://bulletin.fordham.edu/undergraduate/</loc></url></urlset>"
        }

        _ = try await CourseLeafSitemapCache.pageURLs(baseURL: base)
        await CourseLeafSitemapCache.clear()
        _ = try await CourseLeafSitemapCache.pageURLs(baseURL: base)

        XCTAssertEqual(fetchCounter.count, 2)
    }

    func testOrderPageURLsForIngest_programPagesBeforeCoursePages() {
        let urls = [
            URL(string: "https://bulletin.fordham.edu/courses/accounting/")!,
            URL(string: "https://bulletin.fordham.edu/about/")!,
            URL(string: "https://bulletin.fordham.edu/undergraduate/liberal-studies/programs/accounting-bs/")!,
        ]

        let ordered = CourseLeafEngine.orderPageURLsForIngest(urls, schoolID: "fordham_university")

        XCTAssertEqual(ordered.map { $0.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) }, [
            "undergraduate/liberal-studies/programs/accounting-bs",
            "about",
            "courses/accounting",
        ])
    }

    func testOrderPageURLsForIngest_isStableWithinPriorityTiers() {
        let urls = [
            URL(string: "https://bulletins.nyu.edu/courses/zoology/")!,
            URL(string: "https://bulletins.nyu.edu/courses/anthropology/")!,
            URL(string: "https://bulletins.nyu.edu/undergraduate/arts-science/programs/anthropology-ba/")!,
        ]

        let ordered = CourseLeafEngine.orderPageURLsForIngest(urls, schoolID: "new_york_university")

        XCTAssertEqual(
            ordered.first?.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")),
            "undergraduate/arts-science/programs/anthropology-ba"
        )
        XCTAssertEqual(
            ordered.last?.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")),
            "courses/zoology"
        )
        XCTAssertEqual(
            ordered[1].path.trimmingCharacters(in: CharacterSet(charactersIn: "/")),
            "courses/anthropology"
        )
    }
}
