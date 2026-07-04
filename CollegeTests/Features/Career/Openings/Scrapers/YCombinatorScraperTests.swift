// YCombinatorScraperTests.swift
// Feature: Career / Openings / Scrapers

import Foundation
import Testing
@testable import College

@Suite("YCombinatorScraperTests")
struct YCombinatorScraperTests {
    @Test("Parses YC list fixture")
    func parseList() throws {
        let html = try TestFixturePaths.jobBoardString(platform: "YCombinator", named: "ycombinator-list-page-1.html")
        let base = URL(string: "https://www.ycombinator.com/jobs")!
        let listings = JobBoardPublicHubScrapeEngine.parseListings(html: html, baseURL: base, config: .yCombinator)
        #expect(listings.count == 2)
        #expect(listings.contains(where: { $0.title == "Software Engineer" }))
    }
}
