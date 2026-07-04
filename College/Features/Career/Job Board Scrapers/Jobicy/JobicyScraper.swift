// JobicyScraper.swift
// Feature: Career / Job Board Scrapers / Jobicy
// Purpose: Jobicy remote jobs hub scraper.

import Foundation

actor JobicyScraper: JobBoardScraper {
    static let shared = JobicyScraper()
    private let session = JobBoardHTTP.makeSession()
    private let config = PublicHubPlatformConfig.jobicy

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
