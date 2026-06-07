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

    private var bootstrappedHosts: Set<String> = []

    private init() {}

    // MARK: - Public API

    /// Strips query/fragment, `/job/...` detail tails, and trailing `/jobs` (API path, not the board home URL).
    nonisolated static func normalizeCareersURLString(_ urlString: String) -> String {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed) else { return trimmed }
        components.fragment = nil
        components.query = nil

        var segments = components.path.split(separator: "/").map(String.init)
        if let jobIndex = segments.firstIndex(of: "job"), jobIndex > 0 {
            segments = Array(segments.prefix(jobIndex))
        }
        if segments.last?.caseInsensitiveCompare("jobs") == .orderedSame {
            segments.removeLast()
        }
        components.path = segments.isEmpty ? "" : "/" + segments.joined(separator: "/")
        return components.url?.absoluteString ?? trimmed
    }

    nonisolated static func deriveAPIContext(careersURLString: String) -> WorkdayAPIContext? {
        let normalized = normalizeCareersURLString(careersURLString)
        guard let careersURL = URL(string: normalized),
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

        return makeAPIContext(tenant: tenant, board: board, host: host, careersURL: careersURL)
    }

    nonisolated static func parseEmbeddedSiteConfig(from html: String) -> (tenant: String, siteId: String)? {
        guard let tenant = firstRegexCapture(in: html, pattern: #"tenant:\s*"([^"]+)""#),
              let siteId = firstRegexCapture(in: html, pattern: #"siteId:\s*"([^"]+)""#),
              !tenant.isEmpty, !siteId.isEmpty
        else { return nil }
        return (tenant, siteId)
    }

    nonisolated private static func makeAPIContext(
        tenant: String,
        board: String,
        host: String,
        careersURL: URL
    ) -> WorkdayAPIContext? {
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

    nonisolated private static func firstRegexCapture(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text)
        else { return nil }
        return String(text[range])
    }

    nonisolated static func discoverWorkdayBoardURL(from html: String) -> String? {
        let pattern = #"https://[a-z0-9.-]+\.myworkdayjobs\.com(?:/[a-z]{2}(?:-[A-Za-z]{2,4})?(?:-x-[a-z]+)?)?/[^"'\\s<>]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let urlRange = Range(match.range, in: html)
        else { return nil }
        let raw = String(html[urlRange])
        let normalized = normalizeCareersURLString(raw)
        if let context = deriveAPIContext(careersURLString: normalized),
           let canonical = canonicalCareersURL(
               host: context.host,
               board: context.board,
               localePrefix: localePrefix(in: context.careersURL)
           ) {
            return canonical.absoluteString
        }
        return normalized
    }

    nonisolated static func canonicalCareersURL(host: String, board: String, localePrefix: String?) -> URL? {
        var path = ""
        if let localePrefix, !localePrefix.isEmpty {
            path += "/\(localePrefix)"
        }
        path += "/\(board)"
        return URL(string: "https://\(host)\(path)")
    }

    nonisolated static func localePrefix(in careersURL: URL) -> String? {
        let pathComponents = careersURL.path.split(separator: "/").map(String.init)
        guard let first = pathComponents.first else { return nil }
        let localePattern = #"^[a-z]{2,3}(-[A-Za-z]{2,4})?(-x-[a-z]+)?$"#
        guard let localeRegex = try? NSRegularExpression(pattern: localePattern),
              localeRegex.firstMatch(in: first, range: NSRange(first.startIndex..., in: first)) != nil
        else { return nil }
        return first
    }

    func resolveAPIContext(careersURLString: String) async throws -> WorkdayAPIContext {
        let normalized = Self.normalizeCareersURLString(careersURLString)
        if let context = Self.deriveAPIContext(careersURLString: normalized) {
            return try await refineContextFromCareersPage(context)
        }
        return try await deriveAPIContextFromCareersPage(urlString: normalized)
    }

    func scrapeCompanyListings(
        entry: WorkdayCompanyConfigEntry,
        reportProgress: (@Sendable (Int, Int?) -> Void)? = nil
    ) async throws -> [WorkdayScrapedJob] {
        let normalizedURL = Self.normalizeCareersURLString(entry.careersURL)
        var context = try await resolveAPIContext(careersURLString: normalizedURL)

        let scrape: () async throws -> [WorkdayScrapedJob] = {
            try await self.bootstrapCareersSession(context: context)
            let (jobs, facets) = try await self.fetchAllListings(
                context: context,
                appliedFacets: [:],
                reportProgress: reportProgress
            )
            return await self.applyFacetTags(to: jobs, facets: facets, context: context)
        }

        do {
            return try await scrape()
        } catch let error as WorkdayScraperError {
            if case .decodingFailed = error,
               let fallback = try? await deriveAPIContextFromCareersPage(urlString: normalizedURL),
               fallback != context {
                context = fallback
                return try await scrape()
            }
            if case .httpError(404) = error,
               let fallback = try? await deriveAPIContextFromCareersPage(urlString: normalizedURL) {
                context = fallback
                return try await scrape()
            }
            throw error
        }
    }

    func scrapeJobDetail(context: WorkdayAPIContext, externalPath: String) async throws -> WorkdayScrapedDetail {
        guard let url = context.detailURL(externalPath: externalPath) else {
            throw WorkdayScraperError.badURL
        }
        let (data, _) = try await performRequest(
            url: url,
            method: "GET",
            body: nil,
            referer: context.careersURL.absoluteString,
            requestHost: context.host
        )
        do {
            let envelope = try JSONDecoder().decode(WorkdayJobDetailEnvelope.self, from: data)
            return mapDetail(envelope, externalPath: externalPath)
        } catch {
            throw WorkdayScraperError.decodingFailed(error.localizedDescription)
        }
    }

    // MARK: - List pagination

    private func bootstrapCareersSession(context: WorkdayAPIContext, force: Bool = false) async throws {
        guard force || !bootstrappedHosts.contains(context.host) else { return }
        let pageURL = careersPageURL(for: context.careersURL)
        _ = try await performPageRequest(
            url: pageURL,
            referer: pageURL.absoluteString,
            requestHost: context.host
        )
        bootstrappedHosts.insert(context.host)
    }

    private func recoverWorkdaySession(context: WorkdayAPIContext) async throws {
        JobBoardHTTP.resetWorkdaySession()
        bootstrappedHosts.remove(context.host)
        try await bootstrapCareersSession(context: context, force: true)
    }

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
            if expectedTotal == nil || expectedTotal == 0 {
                if let cap = expectedTotalCap, cap > 0 {
                    expectedTotal = cap
                } else if page.total > 0 {
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
    /// Facet enrichment is best-effort — failures must not discard the primary listing scrape.
    private func applyFacetTags(
        to jobs: [WorkdayScrapedJob],
        facets: [WorkdayFacet],
        context: WorkdayAPIContext
    ) async -> [WorkdayScrapedJob] {
        var jobsByPath = Dictionary(uniqueKeysWithValues: jobs.map { ($0.externalPath, $0) })
        let taggableParameters = ["workerSubType", "timeType"]

        for facetParameter in taggableParameters {
            guard let facet = facets.first(where: { $0.facetParameter == facetParameter }),
                  let values = facet.values,
                  !values.isEmpty
            else { continue }

            for value in values {
                if Self.shouldApplyFacetTagInMemory(value: value, jobCount: jobs.count) {
                    Self.applyFacetTagInMemory(
                        value: value,
                        facetParameter: facetParameter,
                        jobsByPath: &jobsByPath
                    )
                    continue
                }
                do {
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
                } catch {
                    continue
                }
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
        do {
            return try await postListPage(context: context, offset: offset, appliedFacets: appliedFacets)
        } catch let error as WorkdayScraperError {
            guard case .network = error else { throw error }
            try await recoverWorkdaySession(context: context)
            return try await postListPage(context: context, offset: offset, appliedFacets: appliedFacets)
        } catch let error as URLError {
            try await recoverWorkdaySession(context: context)
            return try await postListPage(context: context, offset: offset, appliedFacets: appliedFacets)
        }
    }

    private func postListPage(
        context: WorkdayAPIContext,
        offset: Int,
        appliedFacets: [String: [String]]
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
            referer: context.careersURL.absoluteString,
            requestHost: context.host
        )
        do {
            return try WorkdayJobListResponseDecoder.decode(from: data)
        } catch let error as WorkdayScraperError {
            throw error
        } catch {
            throw WorkdayScraperError.decodingFailed(error.localizedDescription)
        }
    }

    private func refineContextFromCareersPage(_ context: WorkdayAPIContext) async throws -> WorkdayAPIContext {
        let pageURL = careersPageURL(for: context.careersURL)
        let (data, _) = try await performPageRequest(
            url: pageURL,
            referer: pageURL.absoluteString,
            requestHost: context.host
        )
        bootstrappedHosts.insert(context.host)
        guard let html = String(data: data, encoding: .utf8),
              let config = Self.parseEmbeddedSiteConfig(from: html),
              let refined = Self.makeAPIContext(
                tenant: config.tenant,
                board: config.siteId,
                host: context.host,
                careersURL: Self.canonicalCareersURL(
                    host: context.host,
                    board: config.siteId,
                    localePrefix: Self.localePrefix(in: context.careersURL)
                ) ?? context.careersURL
              )
        else {
            return context
        }
        return refined
    }

    private func deriveAPIContextFromCareersPage(urlString: String) async throws -> WorkdayAPIContext {
        let normalized = Self.normalizeCareersURLString(urlString)
        guard let url = URL(string: normalized),
              let host = url.host?.lowercased()
        else { throw WorkdayScraperError.badURL }

        if host.contains("myworkdayjobs.com") {
            let fetchURL = careersPageURL(for: url)
            let (data, _) = try await performPageRequest(
                url: fetchURL,
                referer: fetchURL.absoluteString,
                requestHost: host
            )
            bootstrappedHosts.insert(host)
            guard let html = String(data: data, encoding: .utf8),
                  let config = Self.parseEmbeddedSiteConfig(from: html),
                  let context = Self.makeAPIContext(
                    tenant: config.tenant,
                    board: config.siteId,
                    host: host,
                    careersURL: Self.canonicalCareersURL(
                        host: host,
                        board: config.siteId,
                        localePrefix: Self.localePrefix(in: fetchURL)
                    ) ?? fetchURL
                  )
            else {
                throw WorkdayScraperError.badURL
            }
            return context
        }

        let (data, _) = try await JobBoardHTTP.get(url: url)
        guard let html = String(data: data, encoding: .utf8),
              let discovered = Self.discoverWorkdayBoardURL(from: html)
        else {
            throw WorkdayScraperError.badURL
        }
        return try await resolveAPIContext(careersURLString: discovered)
    }

    private func careersPageURL(for url: URL) -> URL {
        if let context = Self.deriveAPIContext(careersURLString: url.absoluteString) {
            return context.careersURL
        }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.query = nil
        components?.fragment = nil
        return components?.url ?? url
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

    private func performPageRequest(
        url: URL,
        referer: String,
        requestHost: String
    ) async throws -> (Data, HTTPURLResponse) {
        var attempt = 0
        var lastError: Error?

        while attempt < maxRetries {
            do {
                return try await JobBoardHTTP.workdayPageRequest(
                    url: url,
                    referer: referer,
                    requestHost: requestHost
                )
            } catch let error as JobBoardScraperError {
                let mapped = error.asWorkdayError
                switch mapped {
                case .httpError(let code) where code == 429:
                    attempt += 1
                    try await backoff(attempt: attempt)
                    lastError = mapped
                case .httpError(let code) where (500...599).contains(code):
                    attempt += 1
                    try await backoff(attempt: attempt)
                    lastError = mapped
                default:
                    throw mapped
                }
            } catch let error as URLError {
                JobBoardHTTP.resetWorkdaySession()
                bootstrappedHosts.remove(requestHost)
                attempt += 1
                lastError = WorkdayScraperError.network(error.localizedDescription)
                if attempt < maxRetries {
                    try await backoff(attempt: attempt)
                }
            } catch {
                if let urlError = error as? URLError {
                    JobBoardHTTP.resetWorkdaySession()
                    bootstrappedHosts.remove(requestHost)
                    throw WorkdayScraperError.network(urlError.localizedDescription)
                }
                throw WorkdayScraperError.decodingFailed(error.localizedDescription)
            }
        }

        if let last = lastError as? WorkdayScraperError, case .network = last {
            throw last
        }
        throw lastError.map { WorkdayScraperError.network($0.localizedDescription) }
            ?? WorkdayScraperError.rateLimited
    }

    private func performRequest(
        url: URL,
        method: String,
        body: Data?,
        referer: String,
        requestHost: String
    ) async throws -> (Data, HTTPURLResponse) {
        var attempt = 0
        var lastError: Error?

        while attempt < maxRetries {
            do {
                return try await JobBoardHTTP.workdayRequest(
                    url: url,
                    method: method,
                    body: body,
                    referer: referer,
                    requestHost: requestHost
                )
            } catch let error as JobBoardScraperError {
                let mapped = error.asWorkdayError
                switch mapped {
                case .httpError(let code) where code == 429:
                    attempt += 1
                    try await backoff(attempt: attempt)
                    lastError = mapped
                case .httpError(let code) where (500...599).contains(code):
                    attempt += 1
                    try await backoff(attempt: attempt)
                    lastError = mapped
                case .httpError(406):
                    throw WorkdayScraperError.httpError(406)
                default:
                    throw mapped
                }
            } catch let error as URLError {
                JobBoardHTTP.resetWorkdaySession()
                bootstrappedHosts.remove(requestHost)
                attempt += 1
                lastError = WorkdayScraperError.network(error.localizedDescription)
                if attempt < maxRetries {
                    try await backoff(attempt: attempt)
                }
            } catch {
                if let urlError = error as? URLError {
                    JobBoardHTTP.resetWorkdaySession()
                    bootstrappedHosts.remove(requestHost)
                    throw WorkdayScraperError.network(urlError.localizedDescription)
                }
                throw WorkdayScraperError.decodingFailed(error.localizedDescription)
            }
        }

        if let last = lastError as? WorkdayScraperError, case .httpError(429) = last {
            throw WorkdayScraperError.rateLimited
        }
        if let last = lastError as? WorkdayScraperError, case .network = last {
            throw last
        }
        throw lastError.map { WorkdayScraperError.network($0.localizedDescription) }
            ?? WorkdayScraperError.rateLimited
    }

    private func randomDelay() async throws {
        guard !CollegeTestRuntime.isUnitTestProcess else { return }
        let ms = UInt64.random(in: 1_000...2_000)
        try await Task.sleep(nanoseconds: ms * 1_000_000_000)
    }

    private func backoff(attempt: Int) async throws {
        let seconds = min(pow(2.0, Double(attempt)), 30.0)
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
}

// MARK: - Facet tagging helpers

extension WorkdayScraper {
    /// When a facet bucket covers the whole board, tag in memory instead of re-paginating the API.
    static func shouldApplyFacetTagInMemory(value: WorkdayFacetValue, jobCount: Int) -> Bool {
        guard jobCount > 0 else { return false }
        guard let count = value.count, count == jobCount else { return false }
        return true
    }

    static func applyFacetTagInMemory(
        value: WorkdayFacetValue,
        facetParameter: String,
        jobsByPath: inout [String: WorkdayScrapedJob]
    ) {
        for path in jobsByPath.keys {
            guard var existing = jobsByPath[path] else { continue }
            switch facetParameter {
            case "workerSubType":
                existing.jobTypeText = value.descriptor
            case "timeType":
                existing.timeType = value.descriptor
            default:
                break
            }
            jobsByPath[path] = existing
        }
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
        let normalized = Self.normalizeCareersURLString(company.careersURL)
        let context = try await resolveAPIContext(careersURLString: normalized)
        guard let path = request.externalPath, !path.isEmpty else { throw JobBoardScraperError.badURL }
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
