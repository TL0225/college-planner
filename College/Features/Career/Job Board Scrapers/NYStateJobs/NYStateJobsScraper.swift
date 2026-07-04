// NYStateJobsScraper.swift
// Feature: Career / Job Board Scrapers / NY State Jobs
// Purpose: New York State civil service vacancies at statejobs.ny.gov.

import Foundation

enum NYStateJobsHTMLParser {
    static func parseListings(html: String) -> [ScrapedJobListing] {
        let pattern = #"vacancyDetailsView\.cfm\?id=(\d+)[^>]*>([^<]+)</a>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [] }
        let range = NSRange(html.startIndex..., in: html)
        var seen = Set<String>()
        var listings: [ScrapedJobListing] = []
        for match in regex.matches(in: html, range: range) {
            guard match.numberOfRanges > 2,
                  let idRange = Range(match.range(at: 1), in: html),
                  let titleRange = Range(match.range(at: 2), in: html)
            else { continue }
            let id = String(html[idRange])
            if seen.contains(id) { continue }
            seen.insert(id)
            let title = decodeHTMLEntities(String(html[titleRange]).trimmingCharacters(in: .whitespacesAndNewlines))
            let path = "vacancyDetailsView.cfm?id=\(id)"
            let applyURL = "https://statejobs.ny.gov/public/\(path)"
            listings.append(
                JobBoardListingNormalizer.normalizeListing(
                    externalId: id,
                    externalPath: path,
                    title: title,
                    locationText: "New York State",
                    postedOn: nil,
                    applyURLString: applyURL,
                    jobTypeText: nil,
                    timeType: nil
                )
            )
        }
        return listings
    }

    static func parseDetail(html: String, fallbackTitle: String?) -> ScrapedJobDetail {
        let fields = parseRowFields(html)
        let title = fields["Title"] ?? fallbackTitle
        var descriptionParts: [String] = []
        if let duties = fields["Duties Description"], !duties.isEmpty {
            descriptionParts.append("Duties\n\(duties)")
        }
        if let min = fields["Minimum Qualifications"], !min.isEmpty {
            descriptionParts.append("Minimum Qualifications\n\(min)")
        }
        if let comments = fields["Additional Comments"], !comments.isEmpty {
            descriptionParts.append("Additional Comments\n\(comments)")
        }
        let location = [fields["County"], fields["City"], fields["State"]]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        return ScrapedJobDetail(
            title: title,
            descriptionPlain: descriptionParts.joined(separator: "\n\n"),
            requirementsPlain: fields["Minimum Qualifications"],
            locationDisplay: location.isEmpty ? fields["County"] : location,
            filterLocations: fields["County"].map { [$0] } ?? [],
            postedAt: parseNYDate(fields["Date Posted"]),
            postedOnDisplay: fields["Date Posted"],
            workModel: teleworkLabel(fields["Telecommuting allowed?"]),
            jobTypeText: fields["Employment Type"],
            timeType: fields["Appointment Type"],
            salaryText: fields["Salary Range"]
        )
    }

    static func parseRowFields(_ html: String) -> [String: String] {
        let pattern = #"<p class="row"><span class="leftCol">([\s\S]*?)</span><span class="rightCol">([\s\S]*?)</span>\s*</p>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [:] }
        var fields: [String: String] = [:]
        let range = NSRange(html.startIndex..., in: html)
        for match in regex.matches(in: html, range: range) {
            guard match.numberOfRanges > 2,
                  let labelRange = Range(match.range(at: 1), in: html),
                  let valueRange = Range(match.range(at: 2), in: html)
            else { continue }
            let label = stripTags(String(html[labelRange])).trimmingCharacters(in: .whitespacesAndNewlines)
            let value = decodeHTMLEntities(stripTags(String(html[valueRange])).trimmingCharacters(in: .whitespacesAndNewlines))
            guard !label.isEmpty else { continue }
            fields[label] = value
        }
        return fields
    }

    private static func stripTags(_ text: String) -> String {
        text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    }

    private static func decodeHTMLEntities(_ text: String) -> String {
        text.replacingOccurrences(of: "&#x28;", with: "(")
            .replacingOccurrences(of: "&#x29;", with: ")")
            .replacingOccurrences(of: "&#x2f;", with: "/")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    private static func parseNYDate(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MM/dd/yy"
        return formatter.date(from: raw)
    }

    private static func teleworkLabel(_ allowed: String?) -> String? {
        guard let allowed else { return nil }
        if allowed.lowercased() == "yes" { return "Telework eligible" }
        return nil
    }
}

actor NYStateJobsScraper: JobBoardScraper {
    static let shared = NYStateJobsScraper()
    private let session = JobBoardHTTP.makeSession()

    static let vacancyTableURL = URL(string: "https://statejobs.ny.gov/public/vacancyTable.cfm")!

    func scrapeListings(
        for company: JobBoardCompany,
        reportProgress: (@Sendable (Int, Int?) -> Void)?,
        onListingsPage: (@Sendable ([ScrapedJobListing]) async -> Void)? = nil
    ) async throws -> [ScrapedJobListing] {
        reportProgress?(0, nil)
        await JobBoardScrapePacing.shared.waitBeforeRequest(platform: .nyStateJobs, host: "statejobs.ny.gov")
        let (data, _) = try await JobBoardHTTP.get(url: Self.vacancyTableURL, session: session)
        guard let html = String(data: data, encoding: .utf8) else {
            throw JobBoardScraperError.decodingFailed("HTML decode failed")
        }
        let listings = Array(NYStateJobsHTMLParser.parseListings(html: html).prefix(JobBoardThresholds.maxListingsPerSync))
        reportProgress?(listings.count, listings.count)
        return listings
    }

    func scrapeDetail(
        request: JobDetailScrapeRequest,
        company: JobBoardCompany
    ) async throws -> ScrapedJobDetail {
        let detailURL: URL
        if let apply = request.applyURLString, let url = URL(string: apply) {
            detailURL = url
        } else if let path = request.externalPath {
            detailURL = URL(string: "https://statejobs.ny.gov/public/\(path)")!
        } else {
            detailURL = URL(string: "https://statejobs.ny.gov/public/vacancyDetailsView.cfm?id=\(request.externalId)")!
        }
        await JobBoardScrapePacing.shared.waitBeforeRequest(platform: .nyStateJobs, host: "statejobs.ny.gov")
        let (data, _) = try await JobBoardHTTP.get(url: detailURL, session: session)
        guard let html = String(data: data, encoding: .utf8) else {
            throw JobBoardScraperError.decodingFailed("HTML decode failed")
        }
        return NYStateJobsHTMLParser.parseDetail(html: html, fallbackTitle: request.fallbackTitle)
    }

    func logoURL(for company: JobBoardCompany) -> URL? {
        URL(string: "https://statejobs.ny.gov/favicon.ico")
    }
}
