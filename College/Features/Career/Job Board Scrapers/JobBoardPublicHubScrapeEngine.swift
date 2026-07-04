// JobBoardPublicHubScrapeEngine.swift
// Feature: Career / Job Board Scrapers
// Purpose: Shared HTML hub pagination + JSON-LD parsing for public job boards.

import Foundation

enum PublicHubPlatformConfig: Sendable {
    case builtIn
    case jobicy
    case remoteOK
    case yCombinator

    var platform: JobBoardPlatform {
        switch self {
        case .builtIn: return .builtIn
        case .jobicy: return .jobicy
        case .remoteOK: return .remoteOK
        case .yCombinator: return .yCombinator
        }
    }

    var listLinkPattern: String {
        switch self {
        case .builtIn:
            return #"href="(/job/[^"]+)""#
        case .jobicy:
            return #"href="(https?://jobicy\.com/jobs/\d+[^"]*|/jobs/\d+[^"]*)""#
        case .remoteOK:
            return #"href="(/remote-jobs/\d+[^"]*)""#
        case .yCombinator:
            return #"href="(/companies/[^"]+/jobs/[^"]+)""#
        }
    }

    func validateHubURL(_ url: URL) -> Bool {
        switch self {
        case .builtIn:
            return JobBoardRobotsPolicy.isAllowedBuiltInHubURL(url)
        case .jobicy:
            let path = url.path.lowercased()
            return url.host?.lowercased().contains("jobicy.com") == true
                && (path.hasPrefix("/remote-jobs") || path.hasPrefix("/jobs"))
        case .remoteOK:
            return url.host?.lowercased().contains("remoteok.com") == true
        case .yCombinator:
            return url.host?.lowercased().contains("ycombinator.com") == true
                && url.path.lowercased().hasPrefix("/jobs")
        }
    }

    func listingPageURL(base: URL, page: Int) -> URL? {
        switch self {
        case .builtIn:
            var components = URLComponents(url: base, resolvingAgainstBaseURL: true)
            if page > 1 {
                components?.queryItems = [URLQueryItem(name: "page", value: String(page))]
            }
            return components?.url
        case .jobicy:
            if page <= 1 { return base }
            var components = URLComponents(url: base, resolvingAgainstBaseURL: true)
            components?.queryItems = [URLQueryItem(name: "page", value: String(page))]
            return components?.url
        case .remoteOK:
            if page <= 1 { return base }
            return URL(string: "\(base.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")))?page=\(page)")
        case .yCombinator:
            if page <= 1 { return base }
            return URL(string: "\(base.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")))?page=\(page)")
        }
    }

    var logoURL: URL? {
        switch self {
        case .builtIn: return URL(string: "https://builtin.com/favicon.ico")
        case .jobicy: return URL(string: "https://jobicy.com/favicon.ico")
        case .remoteOK: return URL(string: "https://remoteok.com/favicon.ico")
        case .yCombinator: return URL(string: "https://www.ycombinator.com/favicon.ico")
        }
    }
}

enum JobBoardPublicHubScrapeEngine {
    static func scrapeListings(
        config: PublicHubPlatformConfig,
        company: JobBoardCompany,
        session: URLSession,
        reportProgress: (@Sendable (Int, Int?) -> Void)?,
        onListingsPage: (@Sendable ([ScrapedJobListing]) async -> Void)? = nil
    ) async throws -> [ScrapedJobListing] {
        guard let base = URL(string: company.careersURL.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw JobBoardScraperError.badURL
        }
        guard config.validateHubURL(base) else {
            throw JobBoardScraperError.decodingFailed("Hub URL is not allowed for this board (robots or format).")
        }
        if let reason = await JobBoardRobotsPolicy.disallowedReason(for: base) {
            throw JobBoardScraperError.decodingFailed(reason)
        }

        var page = 1
        var all: [ScrapedJobListing] = []
        var seenPaths = Set<String>()
        reportProgress?(0, nil)

        while page <= JobBoardThresholds.maxListPagesPerSync, all.count < JobBoardThresholds.maxListingsPerSync {
            guard let pageURL = config.listingPageURL(base: base, page: page) else { break }
            if let reason = await JobBoardRobotsPolicy.disallowedReason(for: pageURL) {
                throw JobBoardScraperError.decodingFailed(reason)
            }
            let host = pageURL.host ?? base.host ?? ""
            await JobBoardScrapePacing.shared.waitBeforeRequest(platform: config.platform, host: host)

            let (data, response) = try await JobBoardHTTP.get(url: pageURL, session: session)
            let html = String(data: data, encoding: .utf8) ?? ""
            if isCloudflareBlock(html: html, statusCode: response.statusCode) {
                throw JobBoardScraperError.rateLimited
            }
            let pageListings = parseListings(html: html, baseURL: pageURL, config: config)
            if pageListings.isEmpty { break }
            var added = 0
            for listing in pageListings where seenPaths.insert(listing.externalPath).inserted {
                all.append(listing)
                added += 1
                if all.count >= JobBoardThresholds.maxListingsPerSync { break }
            }
            reportProgress?(all.count, nil)
            if let onListingsPage, !pageListings.isEmpty {
                await onListingsPage(pageListings)
            }
            if added == 0 { break }
            page += 1
        }

        reportProgress?(all.count, all.count)
        return all
    }

    static func scrapeDetail(
        config: PublicHubPlatformConfig,
        request: JobDetailScrapeRequest,
        company: JobBoardCompany,
        session: URLSession
    ) async throws -> ScrapedJobDetail {
        let detailURL = try resolveDetailURL(request: request, company: company)
        if let reason = await JobBoardRobotsPolicy.disallowedReason(for: detailURL) {
            throw JobBoardScraperError.decodingFailed(reason)
        }
        let host = detailURL.host ?? ""
        await JobBoardScrapePacing.shared.waitBeforeRequest(platform: config.platform, host: host)
        let (data, response) = try await JobBoardHTTP.get(url: detailURL, session: session)
        let html = String(data: data, encoding: .utf8) ?? ""
        if isCloudflareBlock(html: html, statusCode: response.statusCode) {
            throw JobBoardScraperError.rateLimited
        }
        return parseDetailHTML(
            html,
            fallbackTitle: request.fallbackTitle,
            applyURL: request.applyURLString ?? detailURL.absoluteString
        )
    }

    static func parseListings(
        html: String,
        baseURL: URL,
        config: PublicHubPlatformConfig
    ) -> [ScrapedJobListing] {
        guard let regex = try? NSRegularExpression(pattern: config.listLinkPattern, options: .caseInsensitive) else {
            return []
        }
        let range = NSRange(html.startIndex..., in: html)
        var listings: [ScrapedJobListing] = []
        var seen = Set<String>()
        for match in regex.matches(in: html, range: range) {
            guard match.numberOfRanges > 1, let hrefRange = Range(match.range(at: 1), in: html) else { continue }
            let href = String(html[hrefRange])
            let absolute = absoluteURL(href, base: baseURL)
            guard let url = absolute else { continue }
            let path = url.path
            if seen.contains(path) { continue }
            seen.insert(path)
            let title = extractLinkTitle(html: html, href: href) ?? url.lastPathComponent.replacingOccurrences(of: "-", with: " ")
            let externalId = url.lastPathComponent.isEmpty ? path : url.lastPathComponent
            let location = extractNearbyLocation(html: html, href: href)
            let tags = extractNearbyTags(html: html, href: href)
            listings.append(
                JobBoardListingNormalizer.normalizeListing(
                    externalId: externalId,
                    externalPath: path,
                    title: title,
                    locationText: location,
                    postedOn: extractPostedOn(html: html, href: href),
                    applyURLString: url.absoluteString,
                    jobTypeText: nil,
                    timeType: nil,
                    tags: tags
                )
            )
        }
        return listings
    }

    static func parseDetailHTML(
        _ html: String,
        fallbackTitle: String?,
        applyURL: String?
    ) -> ScrapedJobDetail {
        if let posting = JobBoardStructuredDataParser.firstJobPosting(in: html) {
            let plain = posting.descriptionPlain ?? JobBoardHTTP.htmlToPlain(posting.descriptionHTML ?? "")
            return ScrapedJobDetail(
                title: posting.title ?? fallbackTitle,
                descriptionPlain: plain,
                requirementsPlain: nil,
                locationDisplay: posting.locationText,
                filterLocations: posting.locationText.map { [$0] } ?? [],
                postedAt: parseISO8601(posting.datePosted),
                postedOnDisplay: posting.datePosted,
                workModel: JobBoardListingNormalizer.inferTimeType(from: posting.locationText),
                jobTypeText: JobBoardListingNormalizer.inferJobType(from: posting.employmentType),
                timeType: JobBoardListingNormalizer.inferTimeType(from: posting.locationText),
                salaryText: nil
            )
        }
        let title = extractHTMLTitle(html) ?? fallbackTitle
        let body = extractMainContent(html)
        return ScrapedJobDetail(
            title: title,
            descriptionPlain: JobBoardHTTP.htmlToPlain(body),
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

    private static func resolveDetailURL(
        request: JobDetailScrapeRequest,
        company: JobBoardCompany
    ) throws -> URL {
        if let apply = request.applyURLString, let url = URL(string: apply), url.scheme == "https" {
            return url
        }
        guard let base = URL(string: company.careersURL) else { throw JobBoardScraperError.badURL }
        let path = request.externalPath ?? "/job/\(request.externalId)"
        if path.hasPrefix("http"), let url = URL(string: path) { return url }
        if path.hasPrefix("/") {
            guard let host = base.host else { throw JobBoardScraperError.badURL }
            return URL(string: "https://\(host)\(path)")!
        }
        return base.appendingPathComponent(path)
    }

    private static func isCloudflareBlock(html: String, statusCode: Int) -> Bool {
        if statusCode == 403 { return true }
        let lower = html.lowercased()
        return lower.contains("cf-browser-verification")
            || lower.contains("just a moment...")
            || lower.contains("cloudflare")
            && lower.contains("challenge-platform")
    }

    private static func absoluteURL(_ href: String, base: URL) -> URL? {
        if href.hasPrefix("http") { return URL(string: href) }
        if href.hasPrefix("//") { return URL(string: "https:\(href)") }
        if href.hasPrefix("/") {
            guard let host = base.host else { return nil }
            return URL(string: "https://\(host)\(href)")
        }
        return URL(string: href, relativeTo: base)?.absoluteURL
    }

    private static func extractLinkTitle(html: String, href: String) -> String? {
        let fragment = href.split(separator: "/").last.map(String.init) ?? href
        let escaped = NSRegularExpression.escapedPattern(for: fragment)
        let pattern = "href=\"[^\"]*\(escaped)[^\"]*\"[^>]*>([^<]+)<"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              match.numberOfRanges > 1,
              let titleRange = Range(match.range(at: 1), in: html)
        else { return nil }
        let title = String(html[titleRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? nil : title
    }

    private static func extractNearbyLocation(html: String, href: String) -> String? {
        guard let range = html.range(of: href) else { return nil }
        let start = html.index(range.lowerBound, offsetBy: -120, limitedBy: html.startIndex) ?? html.startIndex
        let end = html.index(range.upperBound, offsetBy: 120, limitedBy: html.endIndex) ?? html.endIndex
        let snippet = String(html[start..<end]).lowercased()
        if snippet.contains("remote") { return "Remote" }
        if snippet.contains("hybrid") { return "Hybrid" }
        return nil
    }

    private static func extractNearbyTags(html: String, href: String) -> [String] {
        extractNearbyLocation(html: html, href: href).map { [$0] } ?? []
    }

    private static func extractPostedOn(html: String, href: String) -> String? {
        guard let range = html.range(of: href) else { return nil }
        let end = html.index(range.upperBound, offsetBy: 200, limitedBy: html.endIndex) ?? html.endIndex
        let snippet = String(html[range.lowerBound..<end])
        let pattern = #"(\d{4}-\d{2}-\d{2})"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: snippet, range: NSRange(snippet.startIndex..., in: snippet)),
              let dateRange = Range(match.range(at: 1), in: snippet)
        else { return nil }
        return String(snippet[dateRange])
    }

    private static func extractHTMLTitle(_ html: String) -> String? {
        let pattern = #"<title>([^<]+)</title>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let r = Range(match.range(at: 1), in: html)
        else { return nil }
        return String(html[r]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extractMainContent(_ html: String) -> String {
        let patterns = [
            #"<article[^>]*>([\s\S]*?)</article>"#,
            #"<main[^>]*>([\s\S]*?)</main>"#,
            #"<div[^>]*class="[^"]*description[^"]*"[^>]*>([\s\S]*?)</div>"#
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
               match.numberOfRanges > 1,
               let r = Range(match.range(at: 1), in: html) {
                return String(html[r])
            }
        }
        return html
    }

    private static func parseISO8601(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: raw) { return date }
        formatter.formatOptions = [.withFullDate]
        return formatter.date(from: raw)
    }
}
