// GreenhouseScraper.swift
// Feature: Career / Job Board Scrapers / Greenhouse
// Purpose: Greenhouse job board scraper and API models.
// Data: CollegePersistence / repositories when applicable.

import Foundation

actor GreenhouseScraper: JobBoardScraper {
    static let shared = GreenhouseScraper()
    private let session = JobBoardHTTP.makeSession()

    static func boardToken(from urlString: String) -> String? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let host = url.host?.lowercased() else { return nil }
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let forToken = components.queryItems?.first(where: { $0.name == "for" })?.value,
           !forToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return forToken
        }
        if host.contains("boards.greenhouse.io") {
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
        guard let token = Self.boardToken(from: company.careersURL) else {
            throw JobBoardScraperError.badURL
        }
        reportProgress?(0, nil)
        let url = URL(string: "https://boards-api.greenhouse.io/v1/boards/\(token)/jobs?content=true")!
        let (data, _) = try await JobBoardHTTP.get(url: url, session: session)
        let response = try JSONDecoder().decode(GreenhouseJobsResponse.self, from: data)
        let listings = response.jobs.map { job in
            return ScrapedJobListing(
                externalId: String(job.id),
                externalPath: String(job.id),
                title: job.title,
                locationText: job.location?.name,
                postedOn: job.updatedAt,
                applyURLString: job.absoluteURL,
                jobTypeText: job.departments?.first?.name,
                timeType: nil,
                listingHash: JobListingHash.compute(title: job.title, locationsText: job.location?.name)
            )
        }
        reportProgress?(listings.count, listings.count)
        return listings
    }

    func scrapeDetail(
        request: JobDetailScrapeRequest,
        company: JobBoardCompany
    ) async throws -> ScrapedJobDetail {
        guard let token = Self.boardToken(from: company.careersURL),
              !request.externalId.isEmpty
        else { throw JobBoardScraperError.badURL }
        let url = URL(string: "https://boards-api.greenhouse.io/v1/boards/\(token)/jobs/\(request.externalId)")!
        let (data, _) = try await JobBoardHTTP.get(url: url, session: session)
        let job = try JSONDecoder().decode(GreenhouseJob.self, from: data)
        let plain = job.content.map { JobBoardHTTP.htmlToPlain($0) } ?? request.cachedDescription ?? ""
        return ScrapedJobDetail(
            title: job.title,
            descriptionPlain: plain,
            requirementsPlain: nil,
            locationDisplay: job.location?.name,
            filterLocations: job.location.map { [$0.name] } ?? [],
            postedAt: ISO8601DateFormatter().date(from: job.updatedAt ?? ""),
            postedOnDisplay: job.updatedAt,
            workModel: nil,
            jobTypeText: job.departments?.first?.name,
            timeType: nil,
            salaryText: nil
        )
    }

    func logoURL(for company: JobBoardCompany) -> URL? {
        guard let token = Self.boardToken(from: company.careersURL) else { return nil }
        return URL(string: "https://www.greenhouse.io/logos/\(token).png")
    }
}

private struct GreenhouseJobsResponse: Decodable {
    let jobs: [GreenhouseJob]
}

private struct GreenhouseJob: Decodable {
    let id: Int
    let title: String
    let location: GreenhouseLocation?
    let updatedAt: String?
    let content: String?
    let absoluteURL: String?
    let departments: [GreenhouseDepartment]?

    enum CodingKeys: String, CodingKey {
        case id, title, location, content, departments
        case updatedAt = "updated_at"
        case absoluteURL = "absolute_url"
    }
}

private struct GreenhouseLocation: Decodable {
    let name: String
}

private struct GreenhouseDepartment: Decodable {
    let name: String
}
