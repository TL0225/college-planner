// BuiltInScraperTests.swift
// Feature: Career / Openings / Scrapers

import Foundation
import Testing
@testable import College

@Suite("BuiltInScraperTests")
struct BuiltInScraperTests {
    @Test("Parses list page fixtures")
    func parseListPage() throws {
        let html = try TestFixturePaths.jobBoardString(platform: "BuiltIn", named: "builtin-list-page-1.html")
        let base = URL(string: "https://builtin.com/jobs")!
        let listings = JobBoardPublicHubScrapeEngine.parseListings(
            html: html,
            baseURL: base,
            config: .builtIn
        )
        #expect(listings.count == 2)
        #expect(listings.contains(where: { $0.title == "Software Engineer" && $0.locationText == "Remote" }))
    }

    @Test("Parses detail JSON-LD")
    func parseDetail() throws {
        let html = try TestFixturePaths.jobBoardString(platform: "BuiltIn", named: "builtin-job-detail.html")
        let detail = JobBoardPublicHubScrapeEngine.parseDetailHTML(
            html,
            fallbackTitle: nil,
            applyURL: "https://builtin.com/job/12345"
        )
        #expect(detail.title == "Software Engineer")
        #expect(detail.descriptionPlain.contains("Swift"))
    }

    @Test("Pagination URL for page 2")
    func paginationURL() {
        let base = URL(string: "https://builtin.com/jobs")!
        let page2 = PublicHubPlatformConfig.builtIn.listingPageURL(base: base, page: 2)
        #expect(page2?.absoluteString.contains("page=2") == true)
    }
}
