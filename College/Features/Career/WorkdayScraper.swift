// WorkdayScraper.swift
// Feature: Career
// Purpose: Career module — WorkdayListingHash.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import CryptoKit

/// Serial HTTP client for Workday career board APIs (user IP, no proxy).
actor WorkdayScraper {
    static let shared = WorkdayScraper()

    private let pageSize = 20
    private let maxRetries = 4
    private let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.6 Safari/605.1.15"

    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.urlCache = nil
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        session = URLSession(configuration: config)
    }

    // MARK: - Public API

    nonisolated static func deriveAPIContext(careersURLString: String) -> WorkdayAPIContext? {
        let trimmed = careersURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let careersURL = URL(string: trimmed),
              let host = careersURL.host?.lowercased(),
              host.contains("myworkdayjobs.com")
        else { return nil }

        let pathComponents = careersURL.path.split(separator: "/").map(String.init)
        guard !pathComponents.isEmpty else { return nil }

        let tenant = host.split(separator: ".").first.map(String.init) ?? ""
        guard !tenant.isEmpty else { return nil }

        let localePattern = #"^[a-z]{2,3}(-[A-Za-z]{2,4})?(-x-[a-z]+)?$"#
        let localeRegex = try? NSRegularExpression(pattern: localePattern)
        var boardIndex = 0
        if let first = pathComponents.first,
           localeRegex?.firstMatch(in: first, range: NSRange(first.startIndex..., in: first)) != nil {
            boardIndex = 1
        }
        guard boardIndex < pathComponents.count else { return nil }
        let board = pathComponents[boardIndex]

        let apiBaseString = "https://\(host)/wday/cxs/\(tenant)/\(board)/"
        guard let apiBase = URL(string: apiBaseString) else { return nil }

        return WorkdayAPIContext(
            tenant: tenant,
            board: board,
            host: host,
            apiBase: apiBase,
            careersURL: careersURL
        )
    }

    func scrapeCompanyListings(
        entry: WorkdayCompanyConfigEntry,
        reportProgress: (@Sendable (Int, Int?) -> Void)? = nil
    ) async throws -> [WorkdayScrapedJob] {
        guard let context = Self.deriveAPIContext(careersURLString: entry.careersURL) else {
            throw WorkdayScraperError.badURL
        }
        let (jobs, facets) = try await fetchAllListings(
            context: context,
            appliedFacets: [:],
            reportProgress: reportProgress
        )
        return try await applyFacetTags(to: jobs, facets: facets, context: context)
    }

    func scrapeJobDetail(context: WorkdayAPIContext, externalPath: String) async throws -> WorkdayScrapedDetail {
        guard let url = context.detailURL(externalPath: externalPath) else {
            throw WorkdayScraperError.badURL
        }
        let (data, _) = try await performRequest(url: url, method: "GET", body: nil, context: context)
        do {
            let envelope = try JSONDecoder().decode(WorkdayJobDetailEnvelope.self, from: data)
            return mapDetail(envelope, externalPath: externalPath)
        } catch {
            throw WorkdayScraperError.decodingFailed(error.localizedDescription)
        }
    }

    // MARK: - List pagination

    private func fetchAllListings(
        context: WorkdayAPIContext,
        appliedFacets: [String: [String]],
        expectedTotalCap: Int? = nil,
        reportProgress: (@Sendable (Int, Int?) -> Void)? = nil
    ) async throws -> (jobs: [WorkdayScrapedJob], facets: [WorkdayFacet]) {
        var accumulated: [WorkdayScrapedJob] = []
        var facets: [WorkdayFacet] = []
        var offset = 0
        var expectedTotal: Int?
        reportProgress?(0, nil)

        while true {
            let page = try await fetchListPage(context: context, offset: offset, appliedFacets: appliedFacets)
            if expectedTotal == nil {
                if let cap = expectedTotalCap, cap > 0 {
                    expectedTotal = cap
                } else {
                    expectedTotal = page.total
                }
            }
            if offset == 0, appliedFacets.isEmpty { facets = page.facets ?? [] }
            accumulated.append(contentsOf: page.jobPostings)
            reportProgress?(accumulated.count, expectedTotal)

            let received = page.jobPostings.count
            if received == 0 { break }
            if received < pageSize { break }
            if let total = expectedTotal, accumulated.count >= total { break }

            offset += pageSize
            try await randomDelay()
        }

        return (accumulated, facets)
    }

    /// Tags each posting using Workday list facets (`workerSubType` = Job Type, `timeType` = Time Type).
    private func applyFacetTags(
        to jobs: [WorkdayScrapedJob],
        facets: [WorkdayFacet],
        context: WorkdayAPIContext
    ) async throws -> [WorkdayScrapedJob] {
        var jobsByPath = Dictionary(uniqueKeysWithValues: jobs.map { ($0.externalPath, $0) })
        let taggableParameters = ["workerSubType", "timeType"]

        for facetParameter in taggableParameters {
            guard let facet = facets.first(where: { $0.facetParameter == facetParameter }),
                  let values = facet.values,
                  !values.isEmpty
            else { continue }

            for value in values {
                let (taggedJobs, _) = try await fetchAllListings(
                    context: context,
                    appliedFacets: [facetParameter: [value.id]],
                    expectedTotalCap: value.count
                )
                for job in taggedJobs {
                    guard var existing = jobsByPath[job.externalPath] else { continue }
                    switch facetParameter {
                    case "workerSubType":
                        existing.jobTypeText = value.descriptor
                    case "timeType":
                        existing.timeType = value.descriptor
                    default:
                        break
                    }
                    jobsByPath[job.externalPath] = existing
                }
                try await randomDelay()
            }
        }

        return jobsByPath.values.sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    private func fetchListPage(
        context: WorkdayAPIContext,
        offset: Int,
        appliedFacets: [String: [String]] = [:]
    ) async throws -> WorkdayJobListResponse {
        let body: [String: Any] = [
            "appliedFacets": appliedFacets,
            "limit": pageSize,
            "offset": offset,
            "searchText": "",
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await performRequest(
            url: context.listJobsURL,
            method: "POST",
            body: bodyData,
            context: context
        )
        do {
            return try JSONDecoder().decode(WorkdayJobListResponse.self, from: data)
        } catch {
            throw WorkdayScraperError.decodingFailed(error.localizedDescription)
        }
    }

    private func mapDetail(_ envelope: WorkdayJobDetailEnvelope, externalPath: String) -> WorkdayScrapedDetail {
        let info = envelope.jobPostingInfo
        let description = info?.descriptionPlain ?? ""
        let primary = info?.primaryLocationText
        let additional = info?.additionalLocations
        let filterLocations = WorkdayPostingParsing.resolvedFilterLocations(
            listText: info?.locationsText,
            externalPath: externalPath,
            detailPrimary: primary,
            detailAdditional: additional
        )
        let postedOnDisplay = info?.postedOn?.trimmingCharacters(in: .whitespacesAndNewlines)
        let postedAt = WorkdayPostingParsing.parsePostedOn(postedOnDisplay)
        return WorkdayScrapedDetail(
            title: info?.title,
            jobReqId: info?.jobReqId,
            descriptionPlain: description,
            requirementsPlain: nil,
            workModel: info?.workModelText,
            jobTypeText: nil,
            timeType: info?.timeType,
            salaryText: info?.salaryRangeText,
            locationDisplay: WorkdayPostingParsing.detailLocationDisplay(
                listText: info?.locationsText,
                externalPath: externalPath,
                primary: primary,
                additional: additional
            ),
            filterLocations: filterLocations,
            postedOnDisplay: postedOnDisplay?.isEmpty == false ? postedOnDisplay : nil,
            postedAt: postedAt
        )
    }

    // MARK: - HTTP

    private func performRequest(
        url: URL,
        method: String,
        body: Data?,
        context: WorkdayAPIContext
    ) async throws -> (Data, HTTPURLResponse) {
        var attempt = 0
        var lastError: Error?

        while attempt < maxRetries {
            do {
                return try await singleRequest(url: url, method: method, body: body, requestHost: context.host)
            } catch let error as WorkdayScraperError {
                switch error {
                case .httpError(let code) where code == 429:
                    attempt += 1
                    try await backoff(attempt: attempt)
                    lastError = error
                case .httpError(let code) where (500...599).contains(code):
                    attempt += 1
                    try await backoff(attempt: attempt)
                    lastError = error
                case .httpError(406):
                    // 406 = CDN rejection; no point retrying with the same request.
                    throw WorkdayScraperError.httpError(406)
                default:
                    throw error
                }
            } catch {
                throw error
            }
        }

        if let last = lastError as? WorkdayScraperError, case .httpError(429) = last {
            throw WorkdayScraperError.rateLimited
        }
        throw lastError ?? WorkdayScraperError.rateLimited
    }

    private func singleRequest(
        url: URL,
        method: String,
        body: Data?,
        requestHost: String
    ) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // Cloudflare-protected Workday boards return 406 if Origin/Referer are absent —
        // they expect requests originating from a browser on the same host.
        let origin = "https://\(requestHost)"
        request.setValue(origin, forHTTPHeaderField: "Origin")
        request.setValue(origin + "/", forHTTPHeaderField: "Referer")
        if method == "POST" {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw WorkdayScraperError.decodingFailed("Non-HTTP response")
        }

        if http.statusCode == 401 {
            throw WorkdayScraperError.requiresAuth
        }

        // 406 from Workday/Cloudflare typically means the request was rejected at the
        // CDN layer (missing headers, wrong path, or bot-detection).  Treat as a
        // temporary server error so the coordinator marks the attempt and backs off
        // rather than surfacing an unhelpful "HTTP error 406".
        if http.statusCode == 406 {
            throw WorkdayScraperError.httpError(406)
        }

        if let responseHost = http.url?.host?.lowercased(),
           responseHost != requestHost.lowercased() {
            throw WorkdayScraperError.requiresAuth
        }

        guard (200...299).contains(http.statusCode) else {
            throw WorkdayScraperError.httpError(http.statusCode)
        }

        return (data, http)
    }

    private func randomDelay() async throws {
        let ms = UInt64.random(in: 1_000...2_000)
        try await Task.sleep(nanoseconds: ms * 1_000_000)
    }

    private func backoff(attempt: Int) async throws {
        let seconds = min(pow(2.0, Double(attempt)), 30.0)
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
}

// MARK: - Listing hash (edit detection only; dedup uses externalPath)

enum WorkdayListingHash {
    static func compute(title: String, locationsText: String?) -> String {
        let payload = title + "|" + (locationsText ?? "")
        let digest = SHA256.hash(data: Data(payload.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - JobBoardScraper

extension WorkdayScraper: JobBoardScraper {
    func scrapeListings(
        for company: WorkdayCompanyConfigEntry,
        reportProgress: (@Sendable (Int, Int?) -> Void)?
    ) async throws -> [ScrapedJobListing] {
        let jobs = try await scrapeCompanyListings(entry: company, reportProgress: reportProgress)
        return jobs.map { job in
            ScrapedJobListing(
                externalId: job.stableExternalId,
                externalPath: job.externalPath,
                title: job.title,
                locationText: job.locationsText,
                postedOn: job.postedOn,
                applyURLString: nil,
                jobTypeText: job.jobTypeText,
                timeType: job.timeType,
                listingHash: WorkdayListingHash.compute(title: job.title, locationsText: job.locationsText)
            )
        }
    }

    func scrapeDetail(
        request: JobDetailScrapeRequest,
        company: WorkdayCompanyConfigEntry
    ) async throws -> ScrapedJobDetail {
        guard let context = Self.deriveAPIContext(careersURLString: company.careersURL),
              let path = request.externalPath, !path.isEmpty
        else { throw JobBoardScraperError.badURL }
        let detail = try await scrapeJobDetail(context: context, externalPath: path)
        return ScrapedJobDetail(
            title: detail.title,
            descriptionPlain: detail.descriptionPlain,
            requirementsPlain: detail.requirementsPlain,
            locationDisplay: detail.locationDisplay,
            filterLocations: detail.filterLocations,
            postedAt: detail.postedAt,
            postedOnDisplay: detail.postedOnDisplay,
            workModel: detail.workModel,
            jobTypeText: detail.jobTypeText,
            timeType: detail.timeType,
            salaryText: detail.salaryText
        )
    }

    func logoURL(for company: WorkdayCompanyConfigEntry) -> URL? {
        WorkdayBranding.logoURL(careersURLString: company.careersURL)
    }

    func probeDetailClosed(url: URL) async -> Bool {
        do {
            _ = try await JobBoardHTTP.get(url: url)
            return false
        } catch JobBoardScraperError.httpError(404) {
            return true
        } catch {
            return false
        }
    }
}
