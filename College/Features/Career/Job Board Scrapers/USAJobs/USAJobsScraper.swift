// USAJobsScraper.swift
// Feature: Career / Job Board Scrapers / USAJobs
// Purpose: Federal jobs via the official USAJobs Search API (not HTML scraping).

import Foundation

actor USAJobsScraper: JobBoardScraper {
    static let shared = USAJobsScraper()
    private let session = JobBoardHTTP.makeSession()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        return d
    }()

    func scrapeListings(
        for company: JobBoardCompany,
        reportProgress: (@Sendable (Int, Int?) -> Void)?,
        onListingsPage: (@Sendable ([ScrapedJobListing]) async -> Void)? = nil
    ) async throws -> [ScrapedJobListing] {
        guard JobBoardUSAJobsCredentials.isConfigured else {
            throw JobBoardScraperError.decodingFailed(
                "USAJobs API key and email are required. Add them when tracking USAJobs."
            )
        }
        reportProgress?(0, nil)
        var page = 1
        var all: [ScrapedJobListing] = []
        var seen = Set<String>()

        while page <= JobBoardThresholds.maxListPagesPerSync, all.count < JobBoardThresholds.maxListingsPerSync {
            let response = try await fetchSearch(page: page, keyword: Self.searchKeyword(from: company.careersURL))
            let items = response.searchResult?.searchResultItems ?? []
            if items.isEmpty { break }
            for item in items {
                guard let listing = Self.mapListing(item) else { continue }
                guard seen.insert(listing.externalId).inserted else { continue }
                all.append(listing)
                if all.count >= JobBoardThresholds.maxListingsPerSync { break }
            }
            reportProgress?(all.count, nil)
            if items.count < Self.resultsPerPage { break }
            page += 1
        }
        reportProgress?(all.count, all.count)
        return all
    }

    func scrapeDetail(
        request: JobDetailScrapeRequest,
        company: JobBoardCompany
    ) async throws -> ScrapedJobDetail {
        if let cached = request.cachedDescription, !cached.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return ScrapedJobDetail(
                title: request.fallbackTitle,
                descriptionPlain: cached,
                requirementsPlain: nil,
                locationDisplay: nil,
                filterLocations: [],
                postedAt: nil,
                postedOnDisplay: nil,
                workModel: nil,
                jobTypeText: nil,
                timeType: nil,
                salaryText: nil
            )
        }
        guard JobBoardUSAJobsCredentials.isConfigured else {
            throw JobBoardScraperError.decodingFailed("USAJobs API credentials missing.")
        }
        let positionID = request.externalId
        let response = try await fetchSearch(page: 1, keyword: nil, positionID: positionID)
        guard let item = response.searchResult?.searchResultItems?.first,
              let detail = Self.mapDetail(item, fallbackTitle: request.fallbackTitle)
        else {
            throw JobBoardScraperError.httpError(404)
        }
        return detail
    }

    func logoURL(for company: JobBoardCompany) -> URL? {
        URL(string: "https://www.usajobs.gov/favicon.ico")
    }

    private static let resultsPerPage = 100

    private static func searchKeyword(from careersURL: String) -> String? {
        guard let components = URLComponents(string: careersURL),
              let items = components.queryItems
        else { return nil }
        return items.first(where: { $0.name.lowercased() == "k" || $0.name.lowercased() == "keyword" })?.value
    }

    private func fetchSearch(page: Int, keyword: String?, positionID: String? = nil) async throws -> USAJobsSearchResponse {
        var components = URLComponents(string: "https://data.usajobs.gov/api/search")!
        var query: [URLQueryItem] = [
            URLQueryItem(name: "Page", value: String(page)),
            URLQueryItem(name: "ResultsPerPage", value: String(Self.resultsPerPage)),
        ]
        if let positionID, !positionID.isEmpty {
            query.append(URLQueryItem(name: "PositionID", value: positionID))
        } else if let keyword, !keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            query.append(URLQueryItem(name: "Keyword", value: keyword))
        }
        components.queryItems = query
        guard let url = components.url else { throw JobBoardScraperError.badURL }
        guard let apiKey = JobBoardUSAJobsCredentials.apiKey,
              let email = JobBoardUSAJobsCredentials.userEmail
        else { throw JobBoardScraperError.decodingFailed("USAJobs API credentials missing.") }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("data.usajobs.gov", forHTTPHeaderField: "Host")
        request.setValue(email, forHTTPHeaderField: "User-Agent")
        request.setValue(apiKey, forHTTPHeaderField: "Authorization-Key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw JobBoardScraperError.decodingFailed("Invalid USAJobs response")
        }
        if http.statusCode == 401 {
            throw JobBoardScraperError.requiresAuth
        }
        if http.statusCode == 429 { throw JobBoardScraperError.rateLimited }
        guard (200...299).contains(http.statusCode) else {
            throw JobBoardScraperError.httpError(http.statusCode)
        }
        do {
            return try decoder.decode(USAJobsSearchResponse.self, from: data)
        } catch {
            throw JobBoardScraperError.decodingFailed("USAJobs JSON decode failed: \(error.localizedDescription)")
        }
    }

    static func mapListing(_ item: USAJobsSearchItem) -> ScrapedJobListing? {
        let descriptor = item.matchedObjectDescriptor
        let positionID = descriptor.positionID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !positionID.isEmpty else { return nil }
        let title = descriptor.positionTitle ?? "Federal job \(positionID)"
        let location = descriptor.positionLocationDisplay
        let applyURL = descriptor.applyURI?.first ?? descriptor.positionURI
        let jobType = descriptor.positionOfferingType?.first?.name
            ?? descriptor.positionSchedule?.first?.name
        return JobBoardListingNormalizer.normalizeListing(
            externalId: positionID,
            externalPath: positionID,
            title: title,
            locationText: location,
            postedOn: descriptor.publicationStartDate,
            applyURLString: applyURL,
            jobTypeText: jobType,
            timeType: nil
        )
    }

    static func mapDetail(_ item: USAJobsSearchItem, fallbackTitle: String?) -> ScrapedJobDetail? {
        let descriptor = item.matchedObjectDescriptor
        let details = descriptor.userArea?.details
        var sections: [String] = []
        if let summary = details?.jobSummary, !summary.isEmpty {
            sections.append("Job Summary\n\(summary)")
        }
        if let duties = details?.majorDuties, !duties.isEmpty {
            sections.append("Major Duties\n" + duties.joined(separator: "\n"))
        }
        if let quals = details?.qualificationSummary, !quals.isEmpty {
            sections.append("Qualifications\n\(quals)")
        }
        let descriptionPlain = sections.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !descriptionPlain.isEmpty else { return nil }
        return ScrapedJobDetail(
            title: descriptor.positionTitle ?? fallbackTitle,
            descriptionPlain: descriptionPlain,
            requirementsPlain: details?.qualificationSummary,
            locationDisplay: descriptor.positionLocationDisplay,
            filterLocations: descriptor.positionLocationDisplay.map { [$0] } ?? [],
            postedAt: Self.parseUSAJobsDate(descriptor.publicationStartDate),
            postedOnDisplay: descriptor.publicationStartDate,
            workModel: nil,
            jobTypeText: descriptor.positionOfferingType?.first?.name,
            timeType: descriptor.positionSchedule?.first?.name,
            salaryText: descriptor.positionRemuneration?.first?.minimumRange
        )
    }

    static func parseUSAJobsDate(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: String(raw.prefix(10)))
    }
}

// MARK: - API models

struct USAJobsSearchResponse: Decodable, Sendable {
    var searchResult: USAJobsSearchResult?

    enum CodingKeys: String, CodingKey {
        case searchResult = "SearchResult"
    }
}

struct USAJobsSearchResult: Decodable, Sendable {
    var searchResultItems: [USAJobsSearchItem]?

    enum CodingKeys: String, CodingKey {
        case searchResultItems = "SearchResultItems"
    }
}

struct USAJobsSearchItem: Decodable, Sendable {
    var matchedObjectDescriptor: USAJobsPositionDescriptor

    enum CodingKeys: String, CodingKey {
        case matchedObjectDescriptor = "MatchedObjectDescriptor"
    }
}

struct USAJobsPositionDescriptor: Decodable, Sendable {
    var positionID: String?
    var positionTitle: String?
    var positionURI: String?
    var applyURI: [String]?
    var positionLocationDisplay: String?
    var publicationStartDate: String?
    var positionSchedule: [USAJobsNamedValue]?
    var positionOfferingType: [USAJobsNamedValue]?
    var positionRemuneration: [USAJobsRemuneration]?
    var userArea: USAJobsUserArea?

    enum CodingKeys: String, CodingKey {
        case positionID = "PositionID"
        case positionTitle = "PositionTitle"
        case positionURI = "PositionURI"
        case applyURI = "ApplyURI"
        case positionLocationDisplay = "PositionLocationDisplay"
        case publicationStartDate = "PublicationStartDate"
        case positionSchedule = "PositionSchedule"
        case positionOfferingType = "PositionOfferingType"
        case positionRemuneration = "PositionRemuneration"
        case userArea = "UserArea"
    }
}

struct USAJobsNamedValue: Decodable, Sendable {
    var name: String?

    enum CodingKeys: String, CodingKey {
        case name = "Name"
    }
}

struct USAJobsRemuneration: Decodable, Sendable {
    var minimumRange: String?

    enum CodingKeys: String, CodingKey {
        case minimumRange = "MinimumRange"
    }
}

struct USAJobsUserArea: Decodable, Sendable {
    var details: USAJobsDetails?

    enum CodingKeys: String, CodingKey {
        case details = "Details"
    }
}

struct USAJobsDetails: Decodable, Sendable {
    var jobSummary: String?
    var majorDuties: [String]?
    var qualificationSummary: String?

    enum CodingKeys: String, CodingKey {
        case jobSummary = "JobSummary"
        case majorDuties = "MajorDuties"
        case qualificationSummary = "QualificationSummary"
    }
}
