// YCombinatorScraper.swift
// Feature: Career / Job Board Scrapers / YCombinator
// Purpose: Y Combinator jobs board scraper.

import Foundation

actor YCombinatorScraper: JobBoardScraper {
    static let shared = YCombinatorScraper()
    private let session = JobBoardHTTP.makeSession()
    private let config = PublicHubPlatformConfig.yCombinator

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
