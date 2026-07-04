// USAJobsScraperTests.swift
// Feature: Career / Openings / Scrapers

import Foundation
import Testing
@testable import College

@Suite("USAJobsScraperTests")
struct USAJobsScraperTests {
    @Test("Fixture JSON maps to ScrapedJobListing")
    func mapListingFromFixture() throws {
        let data = try Data(contentsOf: fixtureURL())
        let response = try JSONDecoder().decode(USAJobsSearchResponse.self, from: data)
        let item = try #require(response.searchResult?.searchResultItems?.first)
        let listing = try #require(USAJobsScraper.mapListing(item))
        #expect(listing.externalId == "876543210")
        #expect(listing.title == "IT Specialist (Software)")
        #expect(listing.locationText == "Washington, DC")
        #expect(listing.applyURLString?.contains("usajobs.gov") == true)
        #expect(listing.listingHash != nil)
    }

    @Test("Fixture JSON maps to ScrapedJobDetail")
    func mapDetailFromFixture() throws {
        let data = try Data(contentsOf: fixtureURL())
        let response = try JSONDecoder().decode(USAJobsSearchResponse.self, from: data)
        let item = try #require(response.searchResult?.searchResultItems?.first)
        let detail = try #require(USAJobsScraper.mapDetail(item, fallbackTitle: nil))
        #expect(detail.title == "IT Specialist (Software)")
        #expect(detail.descriptionPlain.contains("Develop and maintain"))
        #expect(detail.requirementsPlain?.contains("specialized experience") == true)
    }

    @Test("Import pipeline accepts USAJobs listing shape")
    @MainActor
    func importPipeline() throws {
        try AppDataStore.shared.clearProfileStoreForUnitTesting()
        let repo = CareerRepository(context: AppDataStore.shared.profileContext)
        let company = JobBoardCompany(
            slug: "usajobs",
            displayName: "USAJobs",
            careersURL: "https://www.usajobs.gov/Search/Results",
            platform: .usajobs
        )
        let data = try Data(contentsOf: fixtureURL())
        let response = try JSONDecoder().decode(USAJobsSearchResponse.self, from: data)
        let listings = (response.searchResult?.searchResultItems ?? []).compactMap(USAJobsScraper.mapListing)
        let count = try repo.applyJobBoardListings(company: company, listings: listings)
        #expect(count == 1)
        #expect(JobBoardReadBridge.companyPostings(companySlug: "usajobs").count == 1)
    }

    private func fixtureURL() throws -> URL {
        try TestFixturePaths.url("JobBoard/USAJobs/usajobs-search-fixture.json")
    }
}
