// NYCCityJobsScraperTests.swift
// Feature: Career / Openings / Scrapers

import Foundation
import Testing
@testable import College

@Suite("NYCCityJobsScraperTests")
struct NYCCityJobsScraperTests {
    @Test("Parses NYC list fixture into ScrapedJobListing rows")
    func parseList() throws {
        let html = try TestFixturePaths.jobBoardString(platform: "NYCCityJobs", named: "nyc-cityjobs-list-page-1.html")
        let base = URL(string: "https://cityjobs.nyc.gov/jobs")!
        let listings = NYCCityJobsHTMLParser.parseListings(html: html, baseURL: base)
        #expect(listings.count >= 2)
        #expect(listings.allSatisfy { $0.externalId.allSatisfy(\.isNumber) })
        #expect(listings.allSatisfy { $0.externalPath.hasPrefix("/job/") })
        #expect(listings.allSatisfy { $0.listingHash != nil })
    }

    @Test("Parses NYC detail fixture into ScrapedJobDetail")
    func parseDetail() throws {
        let html = try TestFixturePaths.jobBoardString(platform: "NYCCityJobs", named: "nyc-cityjobs-job-detail.html")
        let detail = NYCCityJobsHTMLParser.parseDetail(html: html, fallbackTitle: nil)
        #expect(detail.title == "Chief of Staff")
        #expect(!detail.descriptionPlain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    @Test("Import pipeline accepts NYC listing shape")
    @MainActor
    func importPipeline() throws {
        try AppDataStore.shared.clearProfileStoreForUnitTesting()
        let repo = CareerRepository(context: AppDataStore.shared.profileContext)
        let company = JobBoardCompany(
            slug: "nyc-cityjobs",
            displayName: "NYC City Jobs",
            careersURL: "https://cityjobs.nyc.gov/jobs",
            platform: .nycCityJobs
        )
        let html = try TestFixturePaths.jobBoardString(platform: "NYCCityJobs", named: "nyc-cityjobs-list-page-1.html")
        let listings = NYCCityJobsHTMLParser.parseListings(
            html: html,
            baseURL: URL(string: company.careersURL)!
        )
        let count = try repo.applyJobBoardListings(company: company, listings: Array(listings.prefix(5)))
        #expect(count == 5)
    }
}
