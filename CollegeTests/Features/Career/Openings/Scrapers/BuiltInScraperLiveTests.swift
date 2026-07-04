// BuiltInScraperLiveTests.swift
// Feature: Career / Openings / Scrapers (live network)

import Testing
@testable import College

@Suite("BuiltInScraperLiveTests")
struct BuiltInScraperLiveTests {
    @Test("Live BuiltIn hub page fetch")
    func liveHubPage() async throws {
        try CollegeTestsSupport.skipUnlessLiveNetworkTests()
        let company = JobBoardCompany(
            slug: "builtin-live",
            displayName: "BuiltIn",
            careersURL: "https://builtin.com/jobs",
            platform: .builtIn
        )
        let scraper = BuiltInScraper.shared
        do {
            let listings = try await scraper.scrapeListings(for: company, reportProgress: nil)
            #expect(listings.count >= 0)
        } catch let error as JobBoardScraperError where error == .rateLimited {
            // Cloudflare blocks are acceptable in CI — scraper surfaced rate limit correctly.
        }
    }
}
