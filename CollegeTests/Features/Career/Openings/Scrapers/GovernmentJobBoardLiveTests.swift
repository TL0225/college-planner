// GovernmentJobBoardLiveTests.swift
// Feature: Career / Openings / Scrapers (live network)

import Testing
@testable import College

@Suite("GovernmentJobBoardLiveTests")
struct GovernmentJobBoardLiveTests {
    @Test("Live NYC cityjobs scrape returns listings")
    func liveNYCCityJobs() async throws {
        guard CollegeTestRuntime.runLiveNetworkTests else { return }
        let company = JobBoardCompany(
            slug: "nyc-live",
            displayName: "NYC City Jobs",
            careersURL: "https://cityjobs.nyc.gov/jobs",
            platform: .nycCityJobs
        )
        let listings = try await NYCCityJobsScraper.shared.scrapeListings(for: company, reportProgress: nil)
        #expect(listings.count >= 5)
        #expect(listings.allSatisfy { !$0.externalId.isEmpty && $0.listingHash != nil })
    }

    @Test("Live NY State jobs scrape returns listings")
    func liveNYStateJobs() async throws {
        guard CollegeTestRuntime.runLiveNetworkTests else { return }
        let company = JobBoardCompany(
            slug: "ny-state-live",
            displayName: "NY State Jobs",
            careersURL: "https://statejobs.ny.gov/public/vacancyTable.cfm",
            platform: .nyStateJobs
        )
        let listings = try await NYStateJobsScraper.shared.scrapeListings(for: company, reportProgress: nil)
        #expect(listings.count >= 10)
    }

    @Test("Live NYC detail scrape returns description")
    func liveNYCDetail() async throws {
        guard CollegeTestRuntime.runLiveNetworkTests else { return }
        let company = JobBoardCompany(
            slug: "nyc-live",
            displayName: "NYC City Jobs",
            careersURL: "https://cityjobs.nyc.gov/jobs",
            platform: .nycCityJobs
        )
        let listings = try await NYCCityJobsScraper.shared.scrapeListings(for: company, reportProgress: nil)
        let first = try #require(listings.first)
        let detail = try await NYCCityJobsScraper.shared.scrapeDetail(
            request: JobDetailScrapeRequest(
                externalId: first.externalId,
                externalPath: first.externalPath,
                fallbackTitle: first.title,
                applyURLString: first.applyURLString,
                cachedDescription: nil
            ),
            company: company
        )
        #expect(!detail.descriptionPlain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    @Test("Live USAJobs scrape when API credentials configured")
    func liveUSAJobs() async throws {
        guard CollegeTestRuntime.runLiveNetworkTests else { return }
        guard JobBoardUSAJobsCredentials.isConfigured else { return }
        let company = JobBoardCompany(
            slug: "usajobs-live",
            displayName: "USAJobs",
            careersURL: "https://www.usajobs.gov/Search/Results?k=software",
            platform: .usajobs
        )
        let listings = try await USAJobsScraper.shared.scrapeListings(for: company, reportProgress: nil)
        #expect(listings.count >= 1)
    }
}
