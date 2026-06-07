// JobBoardScraper.swift
// Feature: Career
// Purpose: Career module — ScrapedJobListing.
// Data: CollegePersistence / repositories when applicable.

import Foundation

// MARK: - Shared errors

enum JobBoardScraperError: Error, Equatable, Sendable {
    case badURL
    case httpError(Int)
    case requiresAuth
    case decodingFailed(String)
    case rateLimited
    case unsupportedPlatform

    var displayMessage: String {
        switch self {
        case .badURL:
            return "Careers URL format not recognized. Check Settings."
        case .httpError(let code):
            return "HTTP error \(code)"
        case .requiresAuth:
            return "This board may be internal-only (sign-in required)."
        case .decodingFailed(let detail):
            return "Unexpected response format: \(detail)"
        case .rateLimited:
            return "Rate limited — try again later."
        case .unsupportedPlatform:
            return "Unsupported job board platform."
        }
    }
}

extension WorkdayScraperError {
    var asJobBoardError: JobBoardScraperError {
        switch self {
        case .badURL: return .badURL
        case .httpError(let c): return .httpError(c)
        case .requiresAuth: return .requiresAuth
        case .decodingFailed(let d): return .decodingFailed(d)
        case .rateLimited: return .rateLimited
        case .network(let d): return .decodingFailed(d)
        }
    }
}

extension JobBoardScraperError {
    var asWorkdayError: WorkdayScraperError {
        switch self {
        case .badURL: return .badURL
        case .httpError(let c): return .httpError(c)
        case .requiresAuth: return .requiresAuth
        case .decodingFailed(let d):
            if d.localizedCaseInsensitiveContains("offline")
                || d.localizedCaseInsensitiveContains("network")
                || d.localizedCaseInsensitiveContains("connection") {
                return .network(d)
            }
            return .decodingFailed(d)
        case .rateLimited: return .rateLimited
        case .unsupportedPlatform: return .decodingFailed("Unsupported platform")
        }
    }
}

// MARK: - DTOs

struct ScrapedJobListing: Sendable, Equatable {
    let externalId: String
    let externalPath: String
    let title: String
    let locationText: String?
    let postedOn: String?
    let applyURLString: String?
    let jobTypeText: String?
    let timeType: String?
    let listingHash: String?
}

struct ScrapedJobDetail: Sendable, Equatable {
    let title: String?
    let descriptionPlain: String
    let requirementsPlain: String?
    let locationDisplay: String?
    let filterLocations: [String]
    let postedAt: Date?
    let postedOnDisplay: String?
    let workModel: String?
    let jobTypeText: String?
    let timeType: String?
    let salaryText: String?
}

// MARK: - Protocol

struct JobDetailScrapeRequest: Sendable {
    let externalId: String
    let externalPath: String?
    let fallbackTitle: String?
    let applyURLString: String?
    let cachedDescription: String?
}

protocol JobBoardScraper: Actor {
    func scrapeListings(
        for company: WorkdayCompanyConfigEntry,
        reportProgress: (@Sendable (Int, Int?) -> Void)?
    ) async throws -> [ScrapedJobListing]
    func scrapeDetail(
        request: JobDetailScrapeRequest,
        company: WorkdayCompanyConfigEntry
    ) async throws -> ScrapedJobDetail
    func logoURL(for company: WorkdayCompanyConfigEntry) -> URL?
    func probeDetailClosed(url: URL) async -> Bool
}

extension JobBoardScraper {
    func probeDetailClosed(url: URL) async -> Bool { false }
}

// MARK: - Registry

enum JobBoardScraperRegistry {
    static func scraper(for platform: JobBoardPlatform) -> any JobBoardScraper {
        switch platform {
        case .workday: return WorkdayScraper.shared
        case .greenhouse: return GreenhouseScraper.shared
        case .lever: return LeverScraper.shared
        case .oracle: return OracleHCMScraper.shared
        case .icims: return ICIMSScraper.shared
        case .talemetry: return TalemetryScraper.shared
        }
    }

    static func logoURL(for company: WorkdayCompanyConfigEntry) -> URL? {
        switch company.platform {
        case .workday: return WorkdayBranding.logoURL(careersURLString: company.careersURL)
        case .greenhouse: return GreenhouseScraper.boardToken(from: company.careersURL).flatMap {
            URL(string: "https://www.greenhouse.io/logos/\($0).png")
        }
        case .lever:
            guard let url = URL(string: company.careersURL), let host = url.host else { return nil }
            return URL(string: "https://\(host)/favicon.ico")
        case .oracle, .icims, .talemetry:
            guard let url = URL(string: company.careersURL), let host = url.host else { return nil }
            return URL(string: "https://\(host)/favicon.ico")
        }
    }
}

// MARK: - Shared HTTP

enum JobBoardHTTP {
    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.6 Safari/605.1.15"

    /// Long-lived shared session so keep-alive connections survive across sequential requests
    /// and are properly torn down on app exit rather than mid-flight on every call.
    private static let sharedSession: URLSession = makeSession()

    /// Workday CXS API — cookie-capable default session; load careers page before JSON API calls.
    private final class WorkdaySessionBox: @unchecked Sendable {
        private let lock = NSLock()
        private var session: URLSession

        init() {
            session = JobBoardHTTP.makeWorkdaySession()
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
            session = JobBoardHTTP.makeWorkdaySession()
        }
    }

    private static let workdaySessionBox = WorkdaySessionBox()

    static var workdaySession: URLSession {
        workdaySessionBox.current()
    }

    /// Drops stale keep-alive connections after transient network failures.
    static func resetWorkdaySession() {
        workdaySessionBox.reset()
    }

    static func requireHTTPS(_ url: URL) throws {
        guard url.scheme?.lowercased() == "https" else {
            throw JobBoardScraperError.decodingFailed("HTTPS is required for career URLs")
        }
    }

    /// Creates a configured URLSession for callers that manage their own session lifetime
    /// (e.g. long-lived scraper actor singletons). Generic one-shot callers should omit
    /// the `session` parameter in `get()` to reuse the shared session instead.
    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 90
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.httpMaximumConnectionsPerHost = 2
        return URLSession(configuration: config)
    }

    static func makeWorkdaySession() -> URLSession {
        // Ephemeral keeps cookies within this session only (bootstrap + API) without
        // sharing HTTPCookieStorage.default, which can leave stale keep-alive state.
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        config.waitsForConnectivity = false
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.urlCache = nil
        config.httpShouldSetCookies = true
        config.httpCookieAcceptPolicy = .always
        config.httpMaximumConnectionsPerHost = 1
        return URLSession(configuration: config)
    }

    /// Load the public careers HTML page to obtain Cloudflare / session cookies before CXS API calls.
    static func workdayPageRequest(
        url: URL,
        referer: String,
        requestHost: String,
        session: URLSession = sharedSession
    ) async throws -> (Data, HTTPURLResponse) {
        try requireHTTPS(url)
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
            (data, response) = try await session.data(for: request)
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

    /// Workday CXS JSON/HTML request with browser-like headers.
    static func workdayRequest(
        url: URL,
        method: String,
        body: Data? = nil,
        referer: String,
        requestHost: String,
        session: URLSession = sharedSession
    ) async throws -> (Data, HTTPURLResponse) {
        try requireHTTPS(url)
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
            (data, response) = try await session.data(for: request)
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

    /// Pass an explicit `session` only when a caller manages its own session lifetime.
    /// Omitting it reuses the shared long-lived session.
    static func get(
        url: URL,
        session: URLSession? = nil,
        headers: [String: String] = [:]
    ) async throws -> (Data, HTTPURLResponse) {
        try requireHTTPS(url)
        let sess = session ?? sharedSession
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json, text/html, */*", forHTTPHeaderField: "Accept")
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        let (data, response) = try await sess.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw JobBoardScraperError.decodingFailed("Invalid response")
        }
        if http.statusCode == 404 { throw JobBoardScraperError.httpError(404) }
        if http.statusCode == 429 { throw JobBoardScraperError.rateLimited }
        guard (200...299).contains(http.statusCode) else {
            throw JobBoardScraperError.httpError(http.statusCode)
        }
        return (data, http)
    }

    /// Thread-safe HTML → plain text: strips tags with regex and decodes common entities.
    /// Does NOT use WebKit / NSAttributedString so it's safe to call from any thread or actor.
    static func htmlToPlain(_ html: String) -> String {
        guard !html.isEmpty else { return "" }
        var text = html

        // Remove <script> and <style> blocks entirely.
        if let re = try? NSRegularExpression(pattern: "<(script|style)[^>]*>[\\s\\S]*?</\\1>",
                                              options: .caseInsensitive) {
            text = re.stringByReplacingMatches(in: text,
                                               range: NSRange(text.startIndex..., in: text),
                                               withTemplate: " ")
        }

        // Block-level closing tags and <br> → newline.
        if let re = try? NSRegularExpression(pattern: "</(p|div|li|h[1-6]|tr|blockquote)>|<br\\s*/?>",
                                              options: .caseInsensitive) {
            text = re.stringByReplacingMatches(in: text,
                                               range: NSRange(text.startIndex..., in: text),
                                               withTemplate: "\n")
        }

        // Strip remaining tags.
        if let re = try? NSRegularExpression(pattern: "<[^>]+>") {
            text = re.stringByReplacingMatches(in: text,
                                               range: NSRange(text.startIndex..., in: text),
                                               withTemplate: "")
        }

        // Decode common named entities.
        let namedEntities: KeyValuePairs<String, String> = [
            "&amp;": "&", "&lt;": "<", "&gt;": ">", "&nbsp;": " ",
            "&quot;": "\"", "&#39;": "'", "&apos;": "'",
            "&mdash;": "—", "&ndash;": "–",
            "&lsquo;": "\u{2018}", "&rsquo;": "\u{2019}",
            "&ldquo;": "\u{201C}", "&rdquo;": "\u{201D}",
        ]
        for (entity, replacement) in namedEntities {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }

        // Decode numeric character references (&#160; etc.).
        if let re = try? NSRegularExpression(pattern: "&#(\\d+);") {
            let ns = text as NSString
            var result = ""
            var lastEnd = 0
            let matches = re.matches(in: text, range: NSRange(location: 0, length: ns.length))
            for match in matches {
                result += ns.substring(with: NSRange(location: lastEnd, length: match.range.location - lastEnd))
                let numRange = match.range(at: 1)
                let num = ns.substring(with: numRange)
                if let codePoint = UInt32(num), let scalar = Unicode.Scalar(codePoint) {
                    result += String(Character(scalar))
                }
                lastEnd = match.range.location + match.range.length
            }
            result += ns.substring(from: lastEnd)
            text = result
        }

        // Normalise whitespace: collapse blank lines, trim each line.
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        var collapsed: [String] = []
        var prevBlank = false
        for line in lines {
            let blank = line.isEmpty
            if blank && prevBlank { continue }
            collapsed.append(line)
            prevBlank = blank
        }
        return collapsed.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
