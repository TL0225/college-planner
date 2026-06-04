// TalemetryScraper.swift
// Feature: Career
// Purpose: Career module — TalemetryScraper.
// Data: CollegePersistence / repositories when applicable.

import Foundation

actor TalemetryScraper: JobBoardScraper {
    static let shared = TalemetryScraper()
    private let session = JobBoardHTTP.makeSession()

    func scrapeListings(
        for company: WorkdayCompanyConfigEntry,
        reportProgress: (@Sendable (Int, Int?) -> Void)?
    ) async throws -> [ScrapedJobListing] {
        if company.careersURL.lowercased().contains("jobvite.com") {
            return try await scrapeJobviteHosted(company: company, reportProgress: reportProgress)
        }
        return try await scrapeTalemetrySearch(company: company, reportProgress: reportProgress)
    }

    func scrapeDetail(
        request: JobDetailScrapeRequest,
        company: WorkdayCompanyConfigEntry
    ) async throws -> ScrapedJobDetail {
        let base = try baseURL(from: company.careersURL)
        let path = request.externalPath ?? request.externalId
        let detailURL: URL
        if company.careersURL.lowercased().contains("jobvite.com") {
            detailURL = base.appendingPathComponent("job/\(path)")
        } else {
            detailURL = base.appendingPathComponent("jobs/\(path)")
        }
        let (data, _) = try await JobBoardHTTP.get(url: detailURL, session: session)
        guard let html = String(data: data, encoding: .utf8) else {
            throw JobBoardScraperError.decodingFailed("HTML decode failed")
        }
        return parseDetailHTML(html, fallbackTitle: request.fallbackTitle, applyURL: request.applyURLString)
    }

    func logoURL(for company: WorkdayCompanyConfigEntry) -> URL? {
        try? baseURL(from: company.careersURL).appendingPathComponent("favicon.ico")
    }

    private func scrapeJobviteHosted(
        company: WorkdayCompanyConfigEntry,
        reportProgress: (@Sendable (Int, Int?) -> Void)?
    ) async throws -> [ScrapedJobListing] {
        reportProgress?(0, nil)
        let base = try baseURL(from: company.careersURL)
        let (data, _) = try await JobBoardHTTP.get(url: base, session: session)
        guard let html = String(data: data, encoding: .utf8) else { return [] }
        let pattern = #"href="([^"]*/job/[^"]+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [] }
        let range = NSRange(html.startIndex..., in: html)
        var seen = Set<String>()
        var listings: [ScrapedJobListing] = []
        for match in regex.matches(in: html, range: range) {
            guard match.numberOfRanges > 1, let r = Range(match.range(at: 1), in: html) else { continue }
            var href = String(html[r])
            if href.hasPrefix("/") { href = base.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + href }
            guard let url = URL(string: href) else { continue }
            let id = url.lastPathComponent
            if seen.contains(id) { continue }
            seen.insert(id)
            let title = extractLinkTitle(html, hrefFragment: id) ?? "Job \(id)"
            listings.append(ScrapedJobListing(
                externalId: id,
                externalPath: id,
                title: title,
                locationText: nil,
                postedOn: nil,
                applyURLString: url.absoluteString,
                jobTypeText: nil,
                timeType: nil,
                listingHash: WorkdayListingHash.compute(title: title, locationsText: nil)
            ))
        }
        reportProgress?(listings.count, listings.count)
        return listings
    }

    private func scrapeTalemetrySearch(
        company: WorkdayCompanyConfigEntry,
        reportProgress: (@Sendable (Int, Int?) -> Void)?
    ) async throws -> [ScrapedJobListing] {
        let base = try baseURL(from: company.careersURL)
        var page = 1
        var all: [ScrapedJobListing] = []
        var seen = Set<String>()
        reportProgress?(0, nil)
        while page <= 50 {
            var components = URLComponents(url: base.appendingPathComponent("search/jobs"), resolvingAgainstBaseURL: true)!
            if page > 1 { components.queryItems = [URLQueryItem(name: "page", value: String(page))] }
            guard let url = components.url else { break }
            let (data, _) = try await JobBoardHTTP.get(url: url, session: session)
            guard let html = String(data: data, encoding: .utf8) else { break }
            let cards = parseJobCards(html, base: base)
            if cards.isEmpty { break }
            for card in cards where seen.insert(card.externalId).inserted {
                all.append(card)
            }
            reportProgress?(all.count, nil)
            page += 1
        }
        reportProgress?(all.count, all.count)
        return all
    }

    private func parseJobCards(_ html: String, base: URL) -> [ScrapedJobListing] {
        let pattern = #"href="(/jobs/(\d+)[^"]*)""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(html.startIndex..., in: html)
        var listings: [ScrapedJobListing] = []
        var seen = Set<String>()
        for match in regex.matches(in: html, range: range) {
            guard match.numberOfRanges > 2,
                  let pathRange = Range(match.range(at: 1), in: html),
                  let idRange = Range(match.range(at: 2), in: html)
            else { continue }
            let path = String(html[pathRange])
            let id = String(html[idRange])
            if seen.contains(id) { continue }
            seen.insert(id)
            let title = extractNearbyTitle(html, path: path) ?? "Job \(id)"
            let fullURL = URL(string: base.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + path)
            listings.append(ScrapedJobListing(
                externalId: id,
                externalPath: path.trimmingCharacters(in: CharacterSet(charactersIn: "/")),
                title: title,
                locationText: nil,
                postedOn: nil,
                applyURLString: fullURL?.absoluteString,
                jobTypeText: extractJobTypeNear(html, path: path),
                timeType: nil,
                listingHash: WorkdayListingHash.compute(title: title, locationsText: nil)
            ))
        }
        return listings
    }

    private func parseDetailHTML(_ html: String, fallbackTitle: String?, applyURL: String?) -> ScrapedJobDetail {
        let title = extractTag(html, "h1") ?? extractTag(html, "h2") ?? fallbackTitle
        let plain = JobBoardHTTP.htmlToPlain(html)
        _ = extractApplyURL(html) ?? applyURL
        return ScrapedJobDetail(
            title: title,
            descriptionPlain: plain,
            requirementsPlain: nil,
            locationDisplay: extractLabel(html, "Location"),
            filterLocations: [],
            postedAt: nil,
            postedOnDisplay: nil,
            workModel: nil,
            jobTypeText: extractLabel(html, "Job Type"),
            timeType: nil,
            salaryText: extractLabel(html, "Salary")
        )
    }

    private func baseURL(from careersURL: String) throws -> URL {
        guard let url = URL(string: careersURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = url.host
        else { throw JobBoardScraperError.badURL }
        var c = URLComponents()
        c.scheme = url.scheme ?? "https"
        c.host = host
        c.path = url.path.isEmpty ? "/" : url.path
        guard let base = c.url else { throw JobBoardScraperError.badURL }
        return base
    }

    private func extractLinkTitle(_ html: String, hrefFragment: String) -> String? {
        let pattern = #"href="[^"]*\#(hrefFragment)[^"]*"[^>]*>([^<]+)<"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              match.numberOfRanges > 2,
              let r = Range(match.range(at: 2), in: html)
        else { return nil }
        return String(html[r]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func extractNearbyTitle(_ html: String, path: String) -> String? {
        guard let range = html.range(of: path) else { return nil }
        let start = html.index(range.lowerBound, offsetBy: -200, limitedBy: html.startIndex) ?? html.startIndex
        let slice = String(html[start..<range.upperBound])
        return extractTag(slice, "h2") ?? extractTag(slice, "h3")
    }

    private func extractJobTypeNear(_ html: String, path: String) -> String? {
        guard let range = html.range(of: path) else { return nil }
        let end = html.index(range.upperBound, offsetBy: 400, limitedBy: html.endIndex) ?? html.endIndex
        let slice = String(html[range.lowerBound..<end])
        if slice.localizedCaseInsensitiveContains("full-time") { return "Full-time" }
        if slice.localizedCaseInsensitiveContains("part-time") { return "Part-time" }
        return nil
    }

    private func extractApplyURL(_ html: String) -> String? {
        let pattern = #"href="(https://apply\.talemetry\.com[^"]+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              match.numberOfRanges > 1,
              let r = Range(match.range(at: 1), in: html)
        else { return nil }
        return String(html[r])
    }

    private func extractTag(_ html: String, _ tag: String) -> String? {
        let pattern = "<\(tag)[^>]*>([^<]+)</\(tag)>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              match.numberOfRanges > 1,
              let r = Range(match.range(at: 1), in: html)
        else { return nil }
        return String(html[r]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func extractLabel(_ html: String, _ label: String) -> String? {
        if html.localizedCaseInsensitiveContains("\(label):") {
            let pattern = "\(label):\\s*([^<\\n]+)"
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
               match.numberOfRanges > 1,
               let r = Range(match.range(at: 1), in: html) {
                return String(html[r]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }
}
