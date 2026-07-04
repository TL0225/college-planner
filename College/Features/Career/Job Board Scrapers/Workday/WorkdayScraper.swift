// WorkdayScraper.swift
// Feature: Career / Job Board Scrapers / Workday
// Purpose: Workday job board scraper, API models, and HTTP client.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import CryptoKit

// MARK: - Errors

enum WorkdayScraperError: Error, Equatable, Sendable {
    case badURL
    case httpError(Int)
    case requiresAuth
    case decodingFailed(String)
    case rateLimited
    case network(String)

    var displayMessage: String {
        switch self {
        case .badURL:
            return "Careers URL format not recognized. Check Settings."
        case .httpError(let code):
            if code == 404 {
                return "Careers board not found. Use the main board URL from the careers site (not a single job link)."
            }
            if code == 406 {
                return "Request rejected by server (406). Check the careers URL or try again later."
            }
            return "HTTP error \(code)"
        case .requiresAuth:
            return "This board may be internal-only (sign-in required)."
        case .decodingFailed(let detail):
            return "Unexpected response format: \(detail)"
        case .rateLimited:
            return "Rate limited — try again later."
        case .network(let detail):
            return "Network error: \(detail)"
        }
    }
}

// MARK: - API derivation

struct WorkdayAPIContext: Equatable, Sendable {
    let tenant: String
    let board: String
    let host: String
    let apiBase: URL
    let careersURL: URL

    var listJobsURL: URL? {
        var base = apiBase.absoluteString
        while base.hasSuffix("/") { base.removeLast() }
        return URL(string: base + "/jobs")
    }

    func publicJobURL(externalPath: String) -> String? {
        var base = careersURL.absoluteString
        while base.hasSuffix("/") { base.removeLast() }
        let path = externalPath.hasPrefix("/") ? externalPath : "/" + externalPath
        return base + path
    }

    /// Strips careers-page locale/board prefix from listing `externalPath` before appending to `apiBase`.
    func detailURL(externalPath: String) -> URL? {
        let pathSuffix = apiPathSuffix(for: externalPath)
        var base = apiBase.absoluteString
        while base.hasSuffix("/") { base.removeLast() }
        return URL(string: base + pathSuffix)
    }

    private func apiPathSuffix(for externalPath: String) -> String {
        var segments = externalPath.split(separator: "/").map(String.init)
        if let first = segments.first, WorkdayScraper.isLocaleSegment(first) {
            segments.removeFirst()
        }
        if let first = segments.first, first.caseInsensitiveCompare(board) == .orderedSame {
            segments.removeFirst()
        }
        guard !segments.isEmpty else {
            return externalPath.hasPrefix("/") ? externalPath : "/" + externalPath
        }
        return "/" + segments.joined(separator: "/")
    }
}

// MARK: - List response (stable)

private struct WorkdayAPIErrorBody: Decodable, Sendable {
    let errorCode: String?
    let message: String?
    let httpStatus: Int?
}

struct WorkdayJobListResponse: Codable, Sendable {
    let total: Int
    let jobPostings: [WorkdayScrapedJob]
    let facets: [WorkdayFacet]?

    init(total: Int, jobPostings: [WorkdayScrapedJob], facets: [WorkdayFacet]?) {
        self.total = total
        self.jobPostings = jobPostings
        self.facets = facets
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        total = try container.decodeIfPresent(Int.self, forKey: .total) ?? 0
        jobPostings = try container.decodeIfPresent([WorkdayScrapedJob].self, forKey: .jobPostings) ?? []
        facets = try container.decodeIfPresent([WorkdayFacet].self, forKey: .facets)
    }
}

enum WorkdayJobListResponseDecoder {
    private static let decoder = JSONDecoder()

    static func decode(from data: Data) throws -> WorkdayJobListResponse {
        if data.isEmpty {
            throw WorkdayScraperError.decodingFailed("Empty response from Workday jobs API")
        }
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], object.isEmpty {
            throw WorkdayScraperError.decodingFailed(
                "Workday returned an empty JSON object — verify the board URL (e.g. https://insmed.wd5.myworkdayjobs.com/en-US/EXTERNAL) and network/VPN settings"
            )
        }
        let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        if let apiError = try? decoder.decode(WorkdayAPIErrorBody.self, from: data),
           let code = apiError.errorCode?.trimmingCharacters(in: .whitespacesAndNewlines),
           !code.isEmpty,
           jsonObject?["jobPostings"] == nil {
            let message = apiError.message?.trimmingCharacters(in: .whitespacesAndNewlines)
            let detail: String
            if code == "HTTP_422" {
                detail = "Workday rejected the board request (HTTP 422). The careers site may be down for maintenance or the board URL may have changed."
            } else if let message, !message.isEmpty {
                detail = message
            } else {
                detail = code
            }
            throw WorkdayScraperError.decodingFailed("Workday API error: \(detail)")
        }
        do {
            return try decoder.decode(WorkdayJobListResponse.self, from: data)
        } catch {
            let preview = String(data: data.prefix(160), encoding: .utf8)?
                .replacingOccurrences(of: "\n", with: " ")
                ?? "(\(data.count) bytes, non-UTF8)"
            throw WorkdayScraperError.decodingFailed("\(error.localizedDescription) — \(preview)")
        }
    }
}

struct WorkdayFacet: Codable, Sendable {
    let facetParameter: String
    let descriptor: String?
    let values: [WorkdayFacetValue]?

    init(facetParameter: String, descriptor: String?, values: [WorkdayFacetValue]?) {
        self.facetParameter = facetParameter
        self.descriptor = descriptor
        self.values = values
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        facetParameter = try container.decode(String.self, forKey: .facetParameter)
        descriptor = try container.decodeIfPresent(String.self, forKey: .descriptor)
        values = Self.decodeValues(from: container)
    }

    private enum CodingKeys: String, CodingKey {
        case facetParameter, descriptor, values
    }

    /// Workday tenants sometimes nest location facets (`locationMainGroup` → `locationCountry`, etc.).
    /// Tagging only needs flat leaf values (`workerSubType`, `timeType`); ignore nested groups on failure.
    private static func decodeValues(
        from container: KeyedDecodingContainer<CodingKeys>
    ) -> [WorkdayFacetValue]? {
        guard container.contains(.values) else { return nil }
        if let leafValues = try? container.decode([WorkdayFacetValue].self, forKey: .values) {
            return leafValues
        }
        guard let groups = try? container.decode([WorkdayNestedFacetGroup].self, forKey: .values) else {
            return nil
        }
        let flattened = groups.flatMap(\.leafValues)
        return flattened.isEmpty ? nil : flattened
    }
}

/// Nested facet bucket inside `locationMainGroup`-style responses.
private struct WorkdayNestedFacetGroup: Decodable, Sendable {
    let values: [WorkdayFacetValue]?

    var leafValues: [WorkdayFacetValue] {
        values ?? []
    }
}

struct WorkdayFacetValue: Codable, Sendable {
    let descriptor: String
    let id: String
    let count: Int?
}

struct WorkdayScrapedJob: Codable, Sendable {
    let title: String
    let externalPath: String
    let locationsText: String?
    let postedOn: String?
    let bulletFields: [String]?
    /// Workday "Job Type" (`workerSubType` facet), e.g. Regular, Intern (Fixed Term).
    var jobTypeText: String?
    /// Workday "Time Type" (`timeType` facet / detail), e.g. Full time, Part time.
    var timeType: String?

    enum CodingKeys: String, CodingKey {
        case title, externalPath, locationsText, postedOn, bulletFields
    }

    var jobIdDisplayText: String? {
        if let first = bulletFields?.first, !first.isEmpty { return first }
        if let idx = externalPath.lastIndex(of: "_") {
            let suffix = String(externalPath[externalPath.index(after: idx)...])
            if suffix.hasPrefix("R"), suffix.dropFirst().allSatisfy(\.isNumber) {
                return suffix
            }
        }
        return nil
    }

    var stableExternalId: String {
        jobIdDisplayText ?? externalPath
    }
}

// MARK: - Detail response (best-effort; shape varies by tenant)

struct WorkdayJobDetailEnvelope: Codable, Sendable {
    let jobPostingInfo: WorkdayJobPostingInfo?
}

struct WorkdayJobRequisitionLocation: Codable, Sendable {
    let descriptor: String?
}

struct WorkdayJobPostingInfo: Codable, Sendable {
    let title: String?
    let jobReqId: String?
    let locationsText: String?
    let location: String?
    /// Plain text extracted from HTML string or rich-text JSON (shape varies by tenant).
    let descriptionPlain: String
    let timeType: String?
    let remoteType: String?
    let startDate: String?
    let postedOn: String?
    let workLocation: WorkdayWorkLocation?
    let jobRequisitionLocation: WorkdayJobRequisitionLocation?
    let additionalLocations: [String]?
    let payRange: String?
    let compensationGrade: String?

    var salaryRangeText: String? {
        let candidates = [payRange, compensationGrade]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return candidates.first
    }

    var workModelText: String? {
        remoteType ?? workLocation?.remoteType
    }

    var primaryLocationText: String? {
        let candidates = [
            location,
            jobRequisitionLocation?.descriptor,
            locationsText,
        ]
        for candidate in candidates {
            let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmed.isEmpty, !JobBoardPostingParsing.isAggregateLocationCount(trimmed) {
                return trimmed
            }
        }
        return nil
    }

    enum CodingKeys: String, CodingKey {
        case title, jobReqId, locationsText, location, jobDescription, timeType, remoteType
        case startDate, postedOn, workLocation, jobRequisitionLocation, additionalLocations
        case payRange, compensationGrade
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        jobReqId = try container.decodeIfPresent(String.self, forKey: .jobReqId)
        locationsText = try container.decodeIfPresent(String.self, forKey: .locationsText)
        location = try container.decodeIfPresent(String.self, forKey: .location)
        descriptionPlain = Self.decodeDescription(from: container)
        timeType = try container.decodeIfPresent(String.self, forKey: .timeType)
        remoteType = try container.decodeIfPresent(String.self, forKey: .remoteType)
        startDate = try container.decodeIfPresent(String.self, forKey: .startDate)
        postedOn = try container.decodeIfPresent(String.self, forKey: .postedOn)
        workLocation = try container.decodeIfPresent(WorkdayWorkLocation.self, forKey: .workLocation)
        jobRequisitionLocation = try container.decodeIfPresent(
            WorkdayJobRequisitionLocation.self,
            forKey: .jobRequisitionLocation
        )
        if let strings = try? container.decode([String].self, forKey: .additionalLocations) {
            additionalLocations = strings
        } else if let objects = try? container.decode([WorkdayAdditionalLocation].self, forKey: .additionalLocations) {
            additionalLocations = objects.compactMap(\.location).filter { !$0.isEmpty }
        } else {
            additionalLocations = nil
        }
        payRange = try container.decodeIfPresent(String.self, forKey: .payRange)
        compensationGrade = try container.decodeIfPresent(String.self, forKey: .compensationGrade)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(jobReqId, forKey: .jobReqId)
        try container.encodeIfPresent(locationsText, forKey: .locationsText)
        try container.encodeIfPresent(location, forKey: .location)
        try container.encodeIfPresent(timeType, forKey: .timeType)
        try container.encodeIfPresent(remoteType, forKey: .remoteType)
        try container.encodeIfPresent(startDate, forKey: .startDate)
        try container.encodeIfPresent(postedOn, forKey: .postedOn)
        try container.encodeIfPresent(workLocation, forKey: .workLocation)
        try container.encodeIfPresent(jobRequisitionLocation, forKey: .jobRequisitionLocation)
        try container.encodeIfPresent(additionalLocations, forKey: .additionalLocations)
        try container.encodeIfPresent(payRange, forKey: .payRange)
        try container.encodeIfPresent(compensationGrade, forKey: .compensationGrade)
    }
}

struct WorkdayWorkLocation: Codable, Sendable {
    let remoteType: String?
}

struct WorkdayAdditionalLocation: Codable, Sendable {
    let location: String?
}

private struct WorkdayRichText: Codable, Sendable {
    let instances: [WorkdayRichTextNode]?

    func flattenedPlainText() -> String {
        guard let instances else { return "" }
        return instances.compactMap(\.text).joined(separator: "\n")
    }
}

private struct WorkdayRichTextNode: Codable, Sendable {
    let text: String?
}

// MARK: - Description decoding (HTML string vs rich-text object)

extension WorkdayJobPostingInfo {
    fileprivate static func decodeDescription(
        from container: KeyedDecodingContainer<CodingKeys>
    ) -> String {
        if let html = try? container.decode(String.self, forKey: .jobDescription) {
            return JobBoardHTTP.htmlToPlain(html)
        }
        if let rich = try? container.decode(WorkdayRichText.self, forKey: .jobDescription) {
            return rich.flattenedPlainText()
        }
        return ""
    }
}

struct WorkdayScrapedDetail: Sendable {
    let title: String?
    let jobReqId: String?
    let descriptionPlain: String
    let requirementsPlain: String?
    let workModel: String?
    let jobTypeText: String?
    let timeType: String?
    let salaryText: String?
    let locationDisplay: String?
    let filterLocations: [String]
    let postedOnDisplay: String?
    let postedAt: Date?
}
extension WorkdayScraperError {
    var asJobBoardError: JobBoardScraperError {
        switch self {
        case .badURL: return .badURL
        case .httpError(let c): return .httpError(c)
        case .requiresAuth: return .requiresAuth
        case .decodingFailed(let d): return .decodingFailed(d)
        case .rateLimited: return .rateLimited
        case .network(let d): return .network(d)
        }
    }
}

// MARK: - HTTP

enum WorkdayHTTP {
    static let userAgent = JobBoardHTTP.userAgent

    private final class SessionBox: @unchecked Sendable {
        private let lock = NSLock()
        private var session: URLSession

        init() {
            session = WorkdayHTTP.makeSession()
        }

        func current() -> URLSession {
            lock.lock()
            defer { lock.unlock() }
            return session
        }

        func reset() {
            lock.lock()
            defer { lock.unlock() }
            session.invalidateAndCancel()
            session = WorkdayHTTP.makeSession()
        }
    }

    private static let sessionBox = SessionBox()

    static var session: URLSession {
        sessionBox.current()
    }

    static func resetSession() {
        sessionBox.reset()
    }

    static func makeSession() -> URLSession {
        JobBoardHTTP.makeSession(
            httpShouldSetCookies: true,
            acceptsCookies: true,
            httpMaximumConnectionsPerHost: 1,
            timeoutIntervalForResource: 60,
            waitsForConnectivity: false
        )
    }

    static func pageRequest(
        url: URL,
        referer: String,
        requestHost: String,
        session: URLSession? = nil
    ) async throws -> (Data, HTTPURLResponse) {
        let sess = session ?? Self.session
        try JobBoardHTTP.requireHTTPS(url)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue("https://\(requestHost)", forHTTPHeaderField: "Origin")
        request.setValue(referer, forHTTPHeaderField: "Referer")
        request.setValue("close", forHTTPHeaderField: "Connection")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await sess.data(for: request)
        } catch let error as URLError {
            throw error
        } catch {
            throw JobBoardScraperError.decodingFailed(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw JobBoardScraperError.decodingFailed("Invalid response")
        }
        if http.statusCode == 401 { throw JobBoardScraperError.requiresAuth }
        if http.statusCode == 404 { throw JobBoardScraperError.httpError(404) }
        if http.statusCode == 429 { throw JobBoardScraperError.rateLimited }
        guard (200...299).contains(http.statusCode) else {
            throw JobBoardScraperError.httpError(http.statusCode)
        }
        return (data, http)
    }

    static func apiRequest(
        url: URL,
        method: String,
        body: Data? = nil,
        referer: String,
        requestHost: String,
        session: URLSession? = nil
    ) async throws -> (Data, HTTPURLResponse) {
        let sess = session ?? Self.session
        try JobBoardHTTP.requireHTTPS(url)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue("https://\(requestHost)", forHTTPHeaderField: "Origin")
        request.setValue(referer, forHTTPHeaderField: "Referer")
        if method == "POST" {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }
        request.setValue("close", forHTTPHeaderField: "Connection")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await sess.data(for: request)
        } catch let error as URLError {
            throw error
        } catch {
            throw JobBoardScraperError.decodingFailed(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw JobBoardScraperError.decodingFailed("Invalid response")
        }

        if http.statusCode == 401 {
            throw JobBoardScraperError.requiresAuth
        }
        if http.statusCode == 406 {
            throw JobBoardScraperError.httpError(406)
        }
        if let responseHost = http.url?.host?.lowercased(),
           responseHost != requestHost.lowercased(),
           responseHost.contains("myworkday.com"),
           !responseHost.contains("myworkdayjobs.com") {
            throw JobBoardScraperError.requiresAuth
        }
        if http.statusCode == 404 { throw JobBoardScraperError.httpError(404) }
        if http.statusCode == 429 { throw JobBoardScraperError.rateLimited }
        guard (200...299).contains(http.statusCode) else {
            throw JobBoardScraperError.httpError(http.statusCode)
        }
        return (data, http)
    }
}


actor WorkdayScraper {
    static let shared = WorkdayScraper()

    private let pageSize = 20
    private let maxRetries = 4
    private let maxPaginationOffset = 10_000
    private let maxAccumulatedJobs = JobBoardThresholds.maxListingsPerSync

    private var bootstrappedHosts: Set<String> = []

    private init() {}

    // MARK: - Public API

    nonisolated static func delayNanoseconds(forMilliseconds ms: UInt64) -> UInt64 {
        ms * 1_000_000
    }

    nonisolated private static let localeSegmentRegex: NSRegularExpression? = {
        try? NSRegularExpression(
            pattern: #"^[a-z]{2,3}(-[A-Za-z]{2,4})?(-x-[a-z]+)?$"#,
            options: .caseInsensitive
        )
    }()

    nonisolated static func isLocaleSegment(_ segment: String) -> Bool {
        let lower = segment.lowercased()
        // Workday job route segments match `[a-z]{2,3}` but are not locale prefixes.
        if lower == "job" || lower == "jobs" { return false }
        return localeSegmentRegex?.firstMatch(
            in: segment,
            range: NSRange(segment.startIndex..., in: segment)
        ) != nil
    }

    /// Canonical listing path for persistence and deactivate matching (strips locale + board prefix).
    nonisolated static func normalizeListingExternalPath(
        _ externalPath: String,
        board: String? = nil
    ) -> String {
        var trimmed = externalPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        if !trimmed.hasPrefix("/") { trimmed = "/" + trimmed }
        var segments = trimmed.split(separator: "/").map(String.init)
        if let first = segments.first, isLocaleSegment(first) {
            segments.removeFirst()
        }
        if let board, let first = segments.first, first.caseInsensitiveCompare(board) == .orderedSame {
            segments.removeFirst()
        }
        guard !segments.isEmpty else { return trimmed }
        return "/" + segments.joined(separator: "/")
    }

    /// Strips query/fragment, `/job/...` detail tails, and trailing `/jobs` (API path, not the board home URL).
    nonisolated static func normalizeCareersURLString(_ urlString: String) -> String {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed) else { return trimmed }
        components.fragment = nil
        components.query = nil

        var segments = components.path.split(separator: "/").map(String.init)
        if let jobIndex = segments.firstIndex(where: { $0.caseInsensitiveCompare("job") == .orderedSame }),
           jobIndex > 0 {
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

        var boardIndex = 0
        if let first = pathComponents.first, isLocaleSegment(first) {
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

    nonisolated static func throwIfMaintenancePage(html: String) throws {
        if html.localizedCaseInsensitiveContains("community.workday.com/maintenance-page") {
            throw WorkdayScraperError.network(
                "Workday careers site is temporarily down for maintenance."
            )
        }
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
        let pattern = #"https://[a-z0-9.-]+\.myworkdayjobs\.com(?:/[a-z]{2}(?:-[A-Za-z]{2,4})?(?:-x-[a-z]+)?)?/[^"'\s<>]+"#
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
        guard let first = pathComponents.first, isLocaleSegment(first) else { return nil }
        return first
    }

    func resolveAPIContext(
        careersURLString: String,
        visitedURLs: Set<String> = []
    ) async throws -> WorkdayAPIContext {
        let normalized = Self.normalizeCareersURLString(careersURLString)
        guard !visitedURLs.contains(normalized) else {
            throw WorkdayScraperError.badURL
        }
        var visited = visitedURLs
        visited.insert(normalized)
        if let context = Self.deriveAPIContext(careersURLString: normalized) {
            return try await refineContextFromCareersPage(context)
        }
        return try await deriveAPIContextFromCareersPage(urlString: normalized, visitedURLs: visited)
    }

    func scrapeCompanyListings(
        entry: JobBoardCompany,
        reportProgress: (@Sendable (Int, Int?) -> Void)? = nil
    ) async throws -> [WorkdayScrapedJob] {
        let normalizedURL = Self.normalizeCareersURLString(entry.careersURL)
        let context = try await resolveAPIContext(careersURLString: normalizedURL)

        do {
            return try await scrapeListings(using: context, reportProgress: reportProgress)
        } catch let error as WorkdayScraperError {
            guard shouldRetryListingsWithFallback(error),
                  let fallback = try? await deriveAPIContextFromCareersPage(urlString: normalizedURL),
                  fallback != context
            else {
                throw error
            }
            DebugLogger.shared.log(
                "Retrying Workday listing scrape with refined context (board: \(context.board) → \(fallback.board))",
                category: .scraper,
                level: .info
            )
            return try await scrapeListings(using: fallback, reportProgress: reportProgress)
        }
    }

    private func scrapeListings(
        using context: WorkdayAPIContext,
        reportProgress: (@Sendable (Int, Int?) -> Void)?,
        onListingsPage: (@Sendable ([ScrapedJobListing]) async -> Void)? = nil
    ) async throws -> [WorkdayScrapedJob] {
        try await bootstrapCareersSession(context: context)
        let workdayPageHandler = Self.makeWorkdayPageHandler(
            context: context,
            onListingsPage: onListingsPage
        )
        let (jobs, facets) = try await fetchAllListings(
            context: context,
            appliedFacets: [:],
            reportProgress: reportProgress,
            onListingsPage: workdayPageHandler
        )
        return try await applyFacetTags(to: jobs, facets: facets, context: context)
    }

    nonisolated private static func makeWorkdayPageHandler(
        context: WorkdayAPIContext,
        onListingsPage: (@Sendable ([ScrapedJobListing]) async -> Void)?
    ) -> (@Sendable ([WorkdayScrapedJob]) async -> Void)? {
        guard let onListingsPage else { return nil }
        return { pageJobs in
            let listings = mapScrapedListings(pageJobs, context: context)
            await onListingsPage(listings)
        }
    }

    private func shouldRetryListingsWithFallback(_ error: WorkdayScraperError) -> Bool {
        switch error {
        case .decodingFailed, .requiresAuth: return true
        case .httpError(404): return true
        default: return false
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
        WorkdayHTTP.resetSession()
        bootstrappedHosts.remove(context.host)
        try await bootstrapCareersSession(context: context, force: true)
    }

    private func fetchAllListings(
        context: WorkdayAPIContext,
        appliedFacets: [String: [String]],
        expectedTotalCap: Int? = nil,
        reportProgress: (@Sendable (Int, Int?) -> Void)? = nil,
        onListingsPage: (@Sendable ([WorkdayScrapedJob]) async -> Void)? = nil
    ) async throws -> (jobs: [WorkdayScrapedJob], facets: [WorkdayFacet]) {
        var accumulated: [WorkdayScrapedJob] = []
        var facets: [WorkdayFacet] = []
        var offset = 0
        var expectedTotal: Int?
        reportProgress?(0, nil)

        while true {
            if offset > maxPaginationOffset || accumulated.count > maxAccumulatedJobs { break }
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
            if let onListingsPage, !page.jobPostings.isEmpty {
                await onListingsPage(page.jobPostings)
            }

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
    ) async throws -> [WorkdayScrapedJob] {
        var jobsByPath = Dictionary(
            jobs.map { ($0.externalPath, $0) },
            uniquingKeysWith: { _, new in new }
        )
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
                }
                // Partial facet buckets are skipped during list sync — re-paginating the
                // entire board per facet value can take hours on large tenants (e.g. NVIDIA).
                // Job type / time type can still be filled from detail scrapes on demand.
            }
        }

        return jobs.map { jobsByPath[$0.externalPath] ?? $0 }
    }

    private func fetchListPage(
        context: WorkdayAPIContext,
        offset: Int,
        appliedFacets: [String: [String]] = [:]
    ) async throws -> WorkdayJobListResponse {
        do {
            return try await postListPage(context: context, offset: offset, appliedFacets: appliedFacets)
        } catch let error as WorkdayScraperError {
            guard case .network(let detail) = error else { throw error }
            DebugLogger.shared.log(
                "Workday list page network error at offset \(offset); recovering session: \(detail)",
                category: .scraper,
                level: .warn
            )
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
        guard let listURL = context.listJobsURL else { throw WorkdayScraperError.badURL }
        let (data, _) = try await performRequest(
            url: listURL,
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
        guard let html = String(data: data, encoding: .utf8) else {
            return context
        }
        try Self.throwIfMaintenancePage(html: html)
        guard let config = Self.parseEmbeddedSiteConfig(from: html),
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

    private func deriveAPIContextFromCareersPage(
        urlString: String,
        visitedURLs: Set<String> = []
    ) async throws -> WorkdayAPIContext {
        let normalized = Self.normalizeCareersURLString(urlString)
        guard !visitedURLs.contains(normalized) else {
            throw WorkdayScraperError.badURL
        }
        var visited = visitedURLs
        visited.insert(normalized)

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
            guard let html = String(data: data, encoding: .utf8) else {
                throw WorkdayScraperError.badURL
            }
            try Self.throwIfMaintenancePage(html: html)
            guard let config = Self.parseEmbeddedSiteConfig(from: html),
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
        let discoveredNormalized = Self.normalizeCareersURLString(discovered)
        guard !visited.contains(discoveredNormalized) else {
            throw WorkdayScraperError.badURL
        }
        visited.insert(discoveredNormalized)
        guard let context = Self.deriveAPIContext(careersURLString: discoveredNormalized) else {
            throw WorkdayScraperError.badURL
        }
        return try await refineContextFromCareersPage(context)
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
        let filterLocations = JobBoardPostingParsing.resolvedFilterLocations(
            listText: info?.locationsText,
            externalPath: externalPath,
            detailPrimary: primary,
            detailAdditional: additional
        )
        let postedOnDisplay = info?.postedOn?.trimmingCharacters(in: .whitespacesAndNewlines)
        let postedAt = JobBoardPostingParsing.parsePostedOn(postedOnDisplay)
        return WorkdayScrapedDetail(
            title: info?.title,
            jobReqId: info?.jobReqId,
            descriptionPlain: description,
            requirementsPlain: nil,
            workModel: info?.workModelText,
            jobTypeText: nil,
            timeType: info?.timeType,
            salaryText: info?.salaryRangeText,
            locationDisplay: JobBoardPostingParsing.detailLocationDisplay(
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
                return try await WorkdayHTTP.pageRequest(
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
                WorkdayHTTP.resetSession()
                bootstrappedHosts.remove(requestHost)
                attempt += 1
                lastError = WorkdayScraperError.network(error.localizedDescription)
                if attempt < maxRetries {
                    try await backoff(attempt: attempt)
                }
            } catch {
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
                return try await WorkdayHTTP.apiRequest(
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
                WorkdayHTTP.resetSession()
                bootstrappedHosts.remove(requestHost)
                attempt += 1
                lastError = WorkdayScraperError.network(error.localizedDescription)
                if attempt < maxRetries {
                    try await backoff(attempt: attempt)
                }
            } catch {
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
        try await Task.sleep(nanoseconds: Self.delayNanoseconds(forMilliseconds: ms))
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

enum JobListingHash {
    static func compute(title: String, locationsText: String?) -> String {
        let payload = title + "|" + (locationsText ?? "")
        let digest = SHA256.hash(data: Data(payload.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - JobBoardScraper

extension WorkdayScraper: JobBoardScraper {
    func probeBoardFingerprint(for company: JobBoardCompany) async throws -> JobBoardBoardProbeResult? {
        let normalizedURL = Self.normalizeCareersURLString(company.careersURL)
        let context = try await resolveAPIContext(careersURLString: normalizedURL)
        try await bootstrapCareersSession(context: context)
        let page = try await fetchListPage(context: context, offset: 0, appliedFacets: [:])
        let listings = mapScrapedListings(page.jobPostings, context: context)
        let fingerprint = JobBoardBoardFingerprint(
            boardTotal: page.total,
            pageDigest: JobBoardBoardFingerprint.digest(listings: listings)
        )
        return JobBoardBoardProbeResult(fingerprint: fingerprint, firstPageListings: listings)
    }

    func scrapeListings(
        for company: JobBoardCompany,
        reportProgress: (@Sendable (Int, Int?) -> Void)?,
        onListingsPage: (@Sendable ([ScrapedJobListing]) async -> Void)? = nil
    ) async throws -> [ScrapedJobListing] {
        let normalizedURL = Self.normalizeCareersURLString(company.careersURL)
        let context = try await resolveAPIContext(careersURLString: normalizedURL)
        let jobs: [WorkdayScrapedJob]
        do {
            jobs = try await scrapeListings(
                using: context,
                reportProgress: reportProgress,
                onListingsPage: onListingsPage
            )
        } catch let error as WorkdayScraperError {
            guard shouldRetryListingsWithFallback(error),
                  let fallback = try? await deriveAPIContextFromCareersPage(urlString: normalizedURL),
                  fallback != context
            else {
                throw error
            }
            DebugLogger.shared.log(
                "Retrying Workday listing scrape with refined context (board: \(context.board) → \(fallback.board))",
                category: .scraper,
                level: .info
            )
            jobs = try await scrapeListings(
                using: fallback,
                reportProgress: reportProgress,
                onListingsPage: onListingsPage
            )
            return mapScrapedListings(jobs, context: fallback)
        }
        return mapScrapedListings(jobs, context: context)
    }

    nonisolated private static func mapScrapedListings(
        _ jobs: [WorkdayScrapedJob],
        context: WorkdayAPIContext
    ) -> [ScrapedJobListing] {
        jobs.map { job in
            ScrapedJobListing(
                externalId: job.stableExternalId,
                externalPath: normalizeListingExternalPath(job.externalPath, board: context.board),
                title: job.title,
                locationText: job.locationsText,
                postedOn: job.postedOn,
                applyURLString: context.publicJobURL(externalPath: job.externalPath),
                jobTypeText: job.jobTypeText,
                timeType: job.timeType,
                listingHash: JobListingHash.compute(title: job.title, locationsText: job.locationsText)
            )
        }
    }

    private func mapScrapedListings(
        _ jobs: [WorkdayScrapedJob],
        context: WorkdayAPIContext
    ) -> [ScrapedJobListing] {
        Self.mapScrapedListings(jobs, context: context)
    }

    func scrapeDetail(
        request: JobDetailScrapeRequest,
        company: JobBoardCompany
    ) async throws -> ScrapedJobDetail {
        let normalized = Self.normalizeCareersURLString(company.careersURL)
        let context = try await resolveAPIContext(careersURLString: normalized)
        guard let path = request.externalPath, !path.isEmpty else { throw JobBoardScraperError.badURL }
        try await bootstrapCareersSession(context: context)
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

    func logoURL(for company: JobBoardCompany) -> URL? {
        JobBoardBranding.logoURL(careersURLString: company.careersURL)
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