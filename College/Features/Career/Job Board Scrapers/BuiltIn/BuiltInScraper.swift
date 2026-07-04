// BuiltInScraper.swift
// Feature: Career / Job Board Scrapers / BuiltIn
// Purpose: BuiltIn.com public hub scraper (robots-compliant pagination + JSON-LD).

import Foundation

actor BuiltInScraper: JobBoardScraper {
    static let shared = BuiltInScraper()
    private let session = JobBoardHTTP.makeSession()
    private let config = PublicHubPlatformConfig.builtIn

    func scrapeListings(
        for company: JobBoardCompany,
        reportProgress: (@Sendable (Int, Int?) -> Void)?,
        onListingsPage: (@Sendable ([ScrapedJobListing]) async -> Void)? = nil
    ) async throws -> [ScrapedJobListing] {
        try await JobBoardPublicHubScrapeEngine.scrapeListings(
            config: config,
            company: company,
            session: session,
            reportProgress: reportProgress
        )
    }

    func scrapeDetail(
        request: JobDetailScrapeRequest,
        company: JobBoardCompany
    ) async throws -> ScrapedJobDetail {
        try await JobBoardPublicHubScrapeEngine.scrapeDetail(
            config: config,
            request: request,
            company: company,
            session: session
        )
    }

    func logoURL(for company: JobBoardCompany) -> URL? {
        config.logoURL
    }
}
