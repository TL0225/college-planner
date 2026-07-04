// LeverScraper.swift
// Feature: Career / Job Board Scrapers / Lever
// Purpose: Lever job board scraper and API models.
// Data: CollegePersistence / repositories when applicable.

import Foundation

actor LeverScraper: JobBoardScraper {
    static let shared = LeverScraper()
    private let session = JobBoardHTTP.makeSession()

    static func companySlug(from urlString: String) -> String? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let host = url.host?.lowercased() else { return nil }
        if host.contains("jobs.lever.co") || host.contains("lever.co") {
            let parts = url.path.split(separator: "/").map(String.init)
            return parts.first
        }
        return nil
    }

    func scrapeListings(
        for company: JobBoardCompany,
        reportProgress: (@Sendable (Int, Int?) -> Void)?,
        onListingsPage: (@Sendable ([ScrapedJobListing]) async -> Void)? = nil
    ) async throws -> [ScrapedJobListing] {
        guard let slug = Self.companySlug(from: company.careersURL) else {
            throw JobBoardScraperError.badURL
        }
        reportProgress?(0, nil)
        var components = URLComponents(string: "https://api.lever.co/v0/postings/\(slug)")!
        components.queryItems = [
            URLQueryItem(name: "mode", value: "json"),
            URLQueryItem(name: "limit", value: "250"),
        ]
        guard let url = components.url else { throw JobBoardScraperError.badURL }
        let (data, _) = try await JobBoardHTTP.get(url: url, session: session)
        let jobs = try JSONDecoder().decode([LeverPosting].self, from: data)
        let listings = jobs.map { job in
            ScrapedJobListing(
                externalId: job.id,
                externalPath: job.id,
                title: job.text,
                locationText: job.categories?.location,
                postedOn: job.createdAt.map { String($0) },
                applyURLString: job.applyUrl ?? job.hostedUrl,
                jobTypeText: job.categories?.commitment,
                timeType: job.workplaceType,
                listingHash: JobListingHash.compute(title: job.text, locationsText: job.categories?.location)
            )
        }
        reportProgress?(listings.count, listings.count)
        return listings
    }

    func scrapeDetail(
        request: JobDetailScrapeRequest,
        company: JobBoardCompany
    ) async throws -> ScrapedJobDetail {
        guard let slug = Self.companySlug(from: company.careersURL),
              !request.externalId.isEmpty
        else { throw JobBoardScraperError.badURL }
        let id = request.externalId
        let url = URL(string: "https://api.lever.co/v0/postings/\(slug)/\(id)")!
        let (data, _) = try await JobBoardHTTP.get(url: url, session: session)
        let job = try JSONDecoder().decode(LeverPosting.self, from: data)
        let parts = [job.openingPlain, job.descriptionPlain, job.additionalPlain].compactMap { $0 }.filter { !$0.isEmpty }
        let description = parts.joined(separator: "\n\n")
        let posted = job.createdAt.map { Date(timeIntervalSince1970: TimeInterval($0) / 1000) }
        return ScrapedJobDetail(
            title: job.text,
            descriptionPlain: description.isEmpty ? (request.cachedDescription ?? "") : description,
            requirementsPlain: nil,
            locationDisplay: job.categories?.location,
            filterLocations: job.categories?.location.map { [$0] } ?? [],
            postedAt: posted,
            postedOnDisplay: nil,
            workModel: job.workplaceType,
            jobTypeText: job.categories?.commitment,
            timeType: nil,
            salaryText: nil
        )
    }

    func logoURL(for company: JobBoardCompany) -> URL? {
        guard let url = URL(string: company.careersURL), let host = url.host else { return nil }
        return URL(string: "https://\(host)/favicon.ico")
    }
}

private struct LeverPosting: Decodable {
    let id: String
    let text: String
    let createdAt: Int?
    let descriptionPlain: String?
    let openingPlain: String?
    let additionalPlain: String?
    let hostedUrl: String?
    let applyUrl: String?
    let workplaceType: String?
    let categories: LeverCategories?

    enum CodingKeys: String, CodingKey {
        case id, text, categories
        case createdAt
        case descriptionPlain
        case openingPlain
        case additionalPlain
        case hostedUrl
        case applyUrl
        case workplaceType
    }
}

private struct LeverCategories: Decodable {
    let location: String?
    let commitment: String?
    let team: String?
}
