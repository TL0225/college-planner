// JobicyScraperTests.swift
// Feature: Career / Openings / Scrapers

import Foundation
import Testing
@testable import College

@Suite("JobicyScraperTests")
struct JobicyScraperTests {
    @Test("Parses Jobicy list fixture")
    func parseList() throws {
        let html = try TestFixturePaths.jobBoardString(platform: "Jobicy", named: "jobicy-list-page-1.html")
        let base = URL(string: "https://jobicy.com/remote-jobs")!
        let listings = JobBoardPublicHubScrapeEngine.parseListings(html: html, baseURL: base, config: .jobicy)
        #expect(listings.count == 2)
        #expect(listings.first?.title == "Senior Swift Engineer")
    }

    @Test("Parses Jobicy detail fixture")
    func parseDetail() throws {
        let html = try TestFixturePaths.jobBoardString(platform: "Jobicy", named: "jobicy-job-detail.html")
        let detail = JobBoardPublicHubScrapeEngine.parseDetailHTML(html, fallbackTitle: nil, applyURL: nil)
        #expect(detail.title == "Senior Swift Engineer")
    }
}
