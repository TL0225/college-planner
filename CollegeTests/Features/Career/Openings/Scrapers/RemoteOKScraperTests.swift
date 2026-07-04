// RemoteOKScraperTests.swift
// Feature: Career / Openings / Scrapers

import Foundation
import Testing
@testable import College

@Suite("RemoteOKScraperTests")
struct RemoteOKScraperTests {
    @Test("Parses RemoteOK list fixture")
    func parseList() throws {
        let html = try TestFixturePaths.jobBoardString(platform: "RemoteOK", named: "remoteok-list-page-1.html")
        let base = URL(string: "https://remoteok.com")!
        let listings = JobBoardPublicHubScrapeEngine.parseListings(html: html, baseURL: base, config: .remoteOK)
        #expect(listings.count == 2)
        #expect(listings.allSatisfy { $0.timeType == "Remote" })
    }

    @Test("Default pacing delay is 1 second")
    func pacingDelay() {
        #expect(JobBoardScrapePacing.defaultDelay(for: .remoteOK) == 1.0)
    }
}
