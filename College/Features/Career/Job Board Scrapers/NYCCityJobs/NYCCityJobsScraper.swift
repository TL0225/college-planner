// NYCCityJobsScraper.swift
// Feature: Career / Job Board Scrapers / NYC City Jobs
// Purpose: City of New York jobs at cityjobs.nyc.gov.

import Foundation

enum NYCCityJobsHTMLParser {
    static func parseListings(html: String, baseURL: URL) -> [ScrapedJobListing] {
        let pattern = #"href="(/job/[^"]+-jid-\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [] }
        let range = NSRange(html.startIndex..., in: html)
        var seen = Set<String>()
        var listings: [ScrapedJobListing] = []
        for match in regex.matches(in: html, range: range) {
            guard match.numberOfRanges > 1, let pathRange = Range(match.range(at: 1), in: html) else { continue }
            let path = String(html[pathRange])
            if seen.contains(path) { continue }
            seen.insert(path)
            guard let jid = extractJobID(from: path) else { continue }
            let title = titleFromPath(path) ?? "NYC job \(jid)"
            let absolute = URL(string: "https://\(baseURL.host ?? "cityjobs.nyc.gov")\(path)")?.absoluteString
            listings.append(
                JobBoardListingNormalizer.normalizeListing(
                    externalId: jid,
                    externalPath: path,
                    title: title,
                    locationText: locationFromPath(path),
                    postedOn: nil,
                    applyURLString: absolute,
                    jobTypeText: nil,
                    timeType: nil
                )
            )
        }
        return listings
    }

    static func parseDetail(html: String, fallbackTitle: String?) -> ScrapedJobDetail {
        if let posting = JobBoardStructuredDataParser.firstJobPosting(in: html) {
            let plain = posting.descriptionPlain ?? JobBoardHTTP.htmlToPlain(posting.descriptionHTML ?? "")
            return ScrapedJobDetail(
                title: posting.title ?? fallbackTitle,
                descriptionPlain: plain,
                requirementsPlain: nil,
                locationDisplay: posting.locationText,
                filterLocations: posting.locationText.map { [$0] } ?? [],
                postedAt: nil,
                postedOnDisplay: posting.datePosted,
                workModel: JobBoardListingNormalizer.inferTimeType(from: posting.locationText),
                jobTypeText: JobBoardListingNormalizer.inferJobType(from: posting.employmentType),
                timeType: nil,
                salaryText: nil
            )
        }
        let title = extractHeadline(html) ?? fallbackTitle
        let body = extractDescriptionWidget(html)
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

    static func extractJobID(from path: String) -> String? {
        let pattern = #"jid-(\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: path, range: NSRange(path.startIndex..., in: path)),
              let idRange = Range(match.range(at: 1), in: path)
        else { return nil }
        return String(path[idRange])
    }

    private static func titleFromPath(_ path: String) -> String? {
        let slug = path.split(separator: "/").last.map(String.init) ?? path
        let withoutJid = slug.replacingOccurrences(of: #"-jid-\d+$"#, with: "", options: .regularExpression)
        let words = withoutJid.split(separator: "-").map { $0.capitalized }.joined(separator: " ")
        return words.isEmpty ? nil : words
    }

    private static func locationFromPath(_ path: String) -> String? {
        let lower = path.lowercased()
        if lower.contains("-in-remote-") || lower.contains("remote") { return "Remote" }
        for borough in ["manhattan", "brooklyn", "queens", "bronx", "staten-island", "nyc-all-boros"] {
            if lower.contains("-in-\(borough)") {
                return borough.replacingOccurrences(of: "-", with: " ").capitalized
            }
        }
        return "New York City"
    }

    private static func extractHeadline(_ html: String) -> String? {
        let pattern = #"id="headertext"[^>]*>\s*([^<]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let r = Range(match.range(at: 1), in: html)
        else { return nil }
        return String(html[r]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extractDescriptionWidget(_ html: String) -> String {
        let pattern = #"description-widget[^>]*>([\s\S]*?)</div>\s*</div>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let r = Range(match.range(at: 1), in: html)
        else { return "" }
        return String(html[r])
    }
}

actor NYCCityJobsScraper: JobBoardScraper {
    static let shared = NYCCityJobsScraper()
    private let session = JobBoardHTTP.makeSession()

    func scrapeListings(
        for company: JobBoardCompany,
        reportProgress: (@Sendable (Int, Int?) -> Void)?,
        onListingsPage: (@Sendable ([ScrapedJobListing]) async -> Void)? = nil
    ) async throws -> [ScrapedJobListing] {
        guard let base = URL(string: company.careersURL) else { throw JobBoardScraperError.badURL }
        var page = 1
        var all: [ScrapedJobListing] = []
        var seen = Set<String>()
        reportProgress?(0, nil)
        while page <= JobBoardThresholds.maxListPagesPerSync, all.count < JobBoardThresholds.maxListingsPerSync {
            let pageURL = listingURL(base: base, page: page)
            await JobBoardScrapePacing.shared.waitBeforeRequest(platform: .nycCityJobs, host: pageURL.host ?? "cityjobs.nyc.gov")
            let (data, _) = try await JobBoardHTTP.get(url: pageURL, session: session)
            guard let html = String(data: data, encoding: .utf8) else { break }
            let pageListings = NYCCityJobsHTMLParser.parseListings(html: html, baseURL: pageURL)
            if pageListings.isEmpty { break }
            var added = 0
            for listing in pageListings where seen.insert(listing.externalPath).inserted {
                all.append(listing)
                added += 1
                if all.count >= JobBoardThresholds.maxListingsPerSync { break }
            }
            reportProgress?(all.count, nil)
            if added == 0 { break }
            page += 1
        }
        reportProgress?(all.count, all.count)
        return all
    }

    func scrapeDetail(
        request: JobDetailScrapeRequest,
        company: JobBoardCompany
    ) async throws -> ScrapedJobDetail {
        let detailURL = try resolveDetailURL(request: request, company: company)
        await JobBoardScrapePacing.shared.waitBeforeRequest(platform: .nycCityJobs, host: detailURL.host ?? "cityjobs.nyc.gov")
        let (data, _) = try await JobBoardHTTP.get(url: detailURL, session: session)
        guard let html = String(data: data, encoding: .utf8) else {
            throw JobBoardScraperError.decodingFailed("HTML decode failed")
        }
        return NYCCityJobsHTMLParser.parseDetail(html: html, fallbackTitle: request.fallbackTitle)
    }

    func logoURL(for company: JobBoardCompany) -> URL? {
        URL(string: "https://cityjobs.nyc.gov/favicon.ico")
    }

    private func listingURL(base: URL, page: Int) -> URL {
        if page <= 1 { return base }
        var components = URLComponents(url: base, resolvingAgainstBaseURL: true)!
        components.queryItems = [URLQueryItem(name: "page", value: String(page))]
        return components.url ?? base
    }

    private func resolveDetailURL(request: JobDetailScrapeRequest, company: JobBoardCompany) throws -> URL {
        if let apply = request.applyURLString, let url = URL(string: apply) { return url }
        guard let base = URL(string: company.careersURL), let host = base.host else {
            throw JobBoardScraperError.badURL
        }
        if let path = request.externalPath, path.hasPrefix("/job/") {
            return URL(string: "https://\(host)\(path)")!
        }
        throw JobBoardScraperError.badURL
    }
}
