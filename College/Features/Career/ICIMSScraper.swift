// ICIMSScraper.swift
// Feature: Career
// Purpose: Career module — JibeJobWrapper.
// Data: CollegePersistence / repositories when applicable.

import Foundation

actor ICIMSScraper: JobBoardScraper {
    static let shared = ICIMSScraper()
    private let session = JobBoardHTTP.makeSession()
    private static let jibePageSize = 100

    func scrapeListings(
        for company: WorkdayCompanyConfigEntry,
        reportProgress: (@Sendable (Int, Int?) -> Void)?
    ) async throws -> [ScrapedJobListing] {
        let base = try baseURL(from: company.careersURL)
        if await isJibeAPIAvailable(base: base) {
            return try await scrapeJibeListings(base: base, reportProgress: reportProgress)
        }
        reportProgress?(0, nil)
        let sitemapURL = base.appendingPathComponent("sitemap.xml")
        let (data, _) = try await JobBoardHTTP.get(url: sitemapURL, session: session)
        let urls = parseSitemapURLs(data: data, base: base)
        let jobURLs = urls.filter { $0.path.contains("/jobs/") && !$0.path.contains("/jobs/search") }
        var listings: [ScrapedJobListing] = []
        for jobURL in jobURLs.prefix(500) {
            if let id = jobId(from: jobURL) {
                listings.append(ScrapedJobListing(
                    externalId: id,
                    externalPath: id,
                    title: titleFromSlug(jobURL),
                    locationText: nil,
                    postedOn: nil,
                    applyURLString: jobURL.absoluteString,
                    jobTypeText: nil,
                    timeType: nil,
                    listingHash: WorkdayListingHash.compute(title: titleFromSlug(jobURL), locationsText: nil)
                ))
            }
        }
        if listings.isEmpty {
            listings = try await scrapeSearchHTML(base: base)
        }
        reportProgress?(listings.count, listings.count)
        return listings
    }

    func scrapeDetail(
        request: JobDetailScrapeRequest,
        company: WorkdayCompanyConfigEntry
    ) async throws -> ScrapedJobDetail {
        let base = try baseURL(from: company.careersURL)
        if await isJibeAPIAvailable(base: base) {
            return try await scrapeJibeDetail(request: request, base: base)
        }
        let id = request.externalId.isEmpty ? (request.externalPath ?? "") : request.externalId
        let detailURL = base.appendingPathComponent("jobs/\(id)/job")
        var components = URLComponents(url: detailURL, resolvingAgainstBaseURL: true)!
        components.queryItems = [URLQueryItem(name: "in_iframe", value: "1")]
        guard let url = components.url else { throw JobBoardScraperError.badURL }
        let (data, _) = try await JobBoardHTTP.get(url: url, session: session)
        guard let html = String(data: data, encoding: .utf8) else {
            throw JobBoardScraperError.decodingFailed("HTML decode failed")
        }
        return parseJobHTML(html, fallbackTitle: request.fallbackTitle)
    }

    func logoURL(for company: WorkdayCompanyConfigEntry) -> URL? {
        try? baseURL(from: company.careersURL).appendingPathComponent("favicon.ico")
    }

    private func baseURL(from careersURL: String) throws -> URL {
        guard let url = URL(string: careersURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = url.host
        else { throw JobBoardScraperError.badURL }
        var components = URLComponents()
        components.scheme = url.scheme ?? "https"
        components.host = host
        guard let base = components.url else { throw JobBoardScraperError.badURL }
        return base
    }

    private func parseSitemapURLs(data: Data, base: URL) -> [URL] {
        guard let xml = String(data: data, encoding: .utf8) else { return [] }
        let pattern = #"<loc>(.*?)</loc>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(xml.startIndex..., in: xml)
        return regex.matches(in: xml, range: range).compactMap { match -> URL? in
            guard match.numberOfRanges > 1, let r = Range(match.range(at: 1), in: xml) else { return nil }
            let s = String(xml[r]).trimmingCharacters(in: .whitespacesAndNewlines)
            return URL(string: s) ?? base.appendingPathComponent(s)
        }
    }

    private func jobId(from url: URL) -> String? {
        let parts = url.path.split(separator: "/").map(String.init)
        guard let jobsIndex = parts.firstIndex(of: "jobs"), jobsIndex + 1 < parts.count else { return nil }
        let candidate = parts[jobsIndex + 1]
        if candidate == "search" || candidate == "job" { return nil }
        return candidate.allSatisfy(\.isNumber) ? candidate : nil
    }

    private func titleFromSlug(_ url: URL) -> String {
        let parts = url.path.split(separator: "/").map(String.init)
        if parts.count >= 3, parts[0] == "jobs" {
            return parts[2].replacingOccurrences(of: "-", with: " ").capitalized
        }
        return "Job"
    }

    private func scrapeSearchHTML(base: URL) async throws -> [ScrapedJobListing] {
        let searchURL = base.appendingPathComponent("jobs/search")
        var components = URLComponents(url: searchURL, resolvingAgainstBaseURL: true)!
        components.queryItems = [URLQueryItem(name: "in_iframe", value: "1")]
        guard let url = components.url else { return [] }
        let (data, _) = try await JobBoardHTTP.get(url: url, session: session)
        guard let html = String(data: data, encoding: .utf8) else { return [] }
        let pattern = #"href="(/jobs/\d+[^"]*)""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(html.startIndex..., in: html)
        var seen = Set<String>()
        var result: [ScrapedJobListing] = []
        for match in regex.matches(in: html, range: range) {
            guard match.numberOfRanges > 1, let r = Range(match.range(at: 1), in: html) else { continue }
            let path = String(html[r])
            guard let id = jobId(from: URL(string: "https://x.com\(path)")!) else { continue }
            if seen.contains(id) { continue }
            seen.insert(id)
            result.append(ScrapedJobListing(
                externalId: id,
                externalPath: id,
                title: titleFromSlug(URL(string: "https://x.com\(path)")!),
                locationText: nil,
                postedOn: nil,
                applyURLString: base.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))).absoluteString,
                jobTypeText: nil,
                timeType: nil,
                listingHash: WorkdayListingHash.compute(title: id, locationsText: nil)
            ))
        }
        return result
    }

    private func parseJobHTML(_ html: String, fallbackTitle: String?) -> ScrapedJobDetail {
        let title = extractTag(html, tag: "h1") ?? fallbackTitle
        let plain = JobBoardHTTP.htmlToPlain(html)
        let location = extractLabel(html, label: "Location") ?? extractLabel(html, label: "Job Location")
        let jobType = extractLabel(html, label: "Job Type") ?? extractLabel(html, label: "Employment Type")
        return ScrapedJobDetail(
            title: title,
            descriptionPlain: plain,
            requirementsPlain: nil,
            locationDisplay: location,
            filterLocations: location.map { [$0] } ?? [],
            postedAt: nil,
            postedOnDisplay: nil,
            workModel: nil,
            jobTypeText: jobType,
            timeType: nil,
            salaryText: extractLabel(html, label: "Salary")
        )
    }

    private func extractTag(_ html: String, tag: String) -> String? {
        let pattern = "<\(tag)[^>]*>([^<]+)</\(tag)>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              match.numberOfRanges > 1,
              let r = Range(match.range(at: 1), in: html)
        else { return nil }
        return String(html[r]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func extractLabel(_ html: String, label: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: label)
        let pattern = "<dt[^>]*>\\s*\(escaped)\\s*</dt>\\s*<dd[^>]*>([^<]+)</dd>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              match.numberOfRanges > 1,
              let r = Range(match.range(at: 1), in: html)
        else { return nil }
        return String(html[r]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Jibe (iCIMS modern career sites, e.g. careers.jhuapl.edu)

    private func isJibeAPIAvailable(base: URL) async -> Bool {
        guard let url = jibeAPIURL(base: base, page: 1, limit: 1) else { return false }
        do {
            let (data, _) = try await JobBoardHTTP.get(url: url, session: session)
            let root = try JSONDecoder().decode(JibeJobsResponse.self, from: data)
            return !root.jobs.isEmpty
        } catch {
            return false
        }
    }

    private func jibeAPIURL(base: URL, page: Int, limit: Int) -> URL? {
        var components = URLComponents(url: base.appendingPathComponent("api/jobs"), resolvingAgainstBaseURL: true)
        components?.queryItems = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        return components?.url
    }

    private func scrapeJibeListings(
        base: URL,
        reportProgress: (@Sendable (Int, Int?) -> Void)?
    ) async throws -> [ScrapedJobListing] {
        var page = 1
        var all: [ScrapedJobListing] = []
        var totalCount: Int?
        reportProgress?(0, nil)
        while page <= 200 {
            guard let url = jibeAPIURL(base: base, page: page, limit: Self.jibePageSize) else { break }
            let (data, _) = try await JobBoardHTTP.get(url: url, session: session)
            let root = try JSONDecoder().decode(JibeJobsResponse.self, from: data)
            if root.jobs.isEmpty { break }
            if totalCount == nil { totalCount = root.totalCount }
            for entry in root.jobs {
                all.append(listing(from: entry.data, base: base))
            }
            reportProgress?(all.count, totalCount)
            if let total = totalCount, all.count >= total { break }
            if root.jobs.count < Self.jibePageSize { break }
            page += 1
        }
        reportProgress?(all.count, all.count)
        return all
    }

    private func scrapeJibeDetail(request: JobDetailScrapeRequest, base: URL) async throws -> ScrapedJobDetail {
        let lookupIds = jibeLookupIdentifiers(request: request)
        guard !lookupIds.isEmpty else { throw JobBoardScraperError.badURL }

        // Many Jibe sites (e.g. careers.jhuapl.edu) return an HTML SPA shell from
        // /api/jobs/{id} even with HTTP 200 — the listing API includes full job JSON.
        if let job = try await findJibeJobInListings(base: base, lookupIds: lookupIds) {
            return detail(from: job.data, fallbackTitle: request.fallbackTitle)
        }

        for id in lookupIds {
            if let job = try await fetchJibeJobFromDirectAPI(base: base, id: id) {
                return detail(from: job.data, fallbackTitle: request.fallbackTitle)
            }
        }

        if let cached = request.cachedDescription, !cached.isEmpty {
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

        throw JobBoardScraperError.httpError(404)
    }

    private func jibeLookupIdentifiers(request: JobDetailScrapeRequest) -> [String] {
        var seen = Set<String>()
        var ids: [String] = []

        func append(_ raw: String?) {
            let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !trimmed.isEmpty, !seen.contains(trimmed) else { return }
            seen.insert(trimmed)
            ids.append(trimmed)
        }

        append(request.externalPath)
        append(request.externalId)

        if let apply = request.applyURLString, let url = URL(string: apply) {
            let parts = url.path.split(separator: "/").map(String.init)
            if let jobsIndex = parts.firstIndex(of: "jobs"), jobsIndex + 1 < parts.count {
                let candidate = parts[jobsIndex + 1]
                if candidate != "search" && candidate != "job" {
                    append(candidate)
                }
            }
        }

        return ids
    }

    private func fetchJibeJobFromDirectAPI(base: URL, id: String) async throws -> JibeJobEntry? {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        let trimmedBase = base.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(trimmedBase)/api/jobs/\(encoded)") else { return nil }
        do {
            let (data, response) = try await JobBoardHTTP.get(url: url, session: session)
            if isHTMLResponse(data: data, response: response) { return nil }
            if let single = try? JSONDecoder().decode(JibeJobEntry.self, from: data) {
                return single
            }
            struct JibeJobWrapper: Decodable { let job: JibeJobEntry? }
            if let wrapped = try? JSONDecoder().decode(JibeJobWrapper.self, from: data), let job = wrapped.job {
                return job
            }
        } catch JobBoardScraperError.httpError(404) {
            return nil
        } catch {
            return nil
        }
        return nil
    }

    /// Paginates the listing API until a job matches any of the lookup identifiers.
    private func findJibeJobInListings(base: URL, lookupIds: [String]) async throws -> JibeJobEntry? {
        let idSet = Set(lookupIds)
        var page = 1
        while page <= 200 {
            guard let url = jibeAPIURL(base: base, page: page, limit: Self.jibePageSize) else { break }
            let (data, _) = try await JobBoardHTTP.get(url: url, session: session)
            let root = try JSONDecoder().decode(JibeJobsResponse.self, from: data)
            if root.jobs.isEmpty { break }
            if let match = root.jobs.first(where: { entry in
                let data = entry.data
                if idSet.contains(data.slug) { return true }
                if let req = data.reqId, idSet.contains(req) { return true }
                return false
            }) {
                return match
            }
            if let total = root.totalCount, page * Self.jibePageSize >= total { break }
            if root.jobs.count < Self.jibePageSize { break }
            page += 1
        }
        return nil
    }

    private func isHTMLResponse(data: Data, response: HTTPURLResponse) -> Bool {
        if let contentType = response.value(forHTTPHeaderField: "Content-Type")?.lowercased(),
           contentType.contains("text/html") {
            return true
        }
        guard let prefix = String(data: data.prefix(256), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        else { return false }
        return prefix.hasPrefix("<!doctype") || prefix.hasPrefix("<html")
    }

    private func listing(from data: JibeJobData, base: URL) -> ScrapedJobListing {
        let id = data.reqId ?? data.slug
        let location = jibeLocationText(data)
        let applyURL = base.appendingPathComponent("jobs/\(data.slug)").absoluteString
        let (postedOn, _) = jibePostedFields(data)
        return ScrapedJobListing(
            externalId: id,
            externalPath: data.slug,
            title: data.title,
            locationText: location,
            postedOn: postedOn,
            applyURLString: applyURL,
            jobTypeText: data.categories?.first ?? data.department,
            timeType: nil,
            listingHash: WorkdayListingHash.compute(title: data.title, locationsText: location)
        )
    }

    private func detail(from data: JibeJobData, fallbackTitle: String?) -> ScrapedJobDetail {
        let plain = data.description.map { JobBoardHTTP.htmlToPlain($0) } ?? ""
        let location = jibeLocationText(data)
        let salary = jibeSalaryText(data)
        let (postedOn, postedAt) = jibePostedFields(data)
        return ScrapedJobDetail(
            title: data.title.isEmpty ? fallbackTitle : data.title,
            descriptionPlain: plain,
            requirementsPlain: nil,
            locationDisplay: location,
            filterLocations: location.map { [$0] } ?? [],
            postedAt: postedAt,
            postedOnDisplay: postedOn,
            workModel: data.locationType,
            jobTypeText: data.categories?.first ?? data.department,
            timeType: nil,
            salaryText: salary
        )
    }

    private func jibePostedFields(_ data: JibeJobData) -> (display: String?, date: Date?) {
        guard let raw = data.postedDate?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return (nil, nil)
        }
        let parsed = WorkdayPostingParsing.parsePostedOn(raw)
            ?? WorkdayPostingParsing.parseISODate(raw)
        if let parsed {
            return (parsed.formatted(date: .abbreviated, time: .omitted), parsed)
        }
        return (raw, nil)
    }

    private func jibeLocationText(_ data: JibeJobData) -> String? {
        if let name = data.locationName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        let parts = [data.city, data.state, data.country].compactMap { part -> String? in
            guard let part, !part.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return part
        }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    private func jibeSalaryText(_ data: JibeJobData) -> String? {
        if let text = data.salaryValueText?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            return text
        }
        return nil
    }
}

// MARK: - Jibe JSON

private struct JibeJobsResponse: Decodable {
    let jobs: [JibeJobEntry]
    let totalCount: Int?

    enum CodingKeys: String, CodingKey {
        case jobs
        case totalCount
    }
}

private struct JibeJobEntry: Decodable {
    let data: JibeJobData
}

private struct JibeJobData: Decodable {
    let slug: String
    let reqId: String?
    let title: String
    let description: String?
    let locationName: String?
    let city: String?
    let state: String?
    let country: String?
    let locationType: String?
    let categories: [String]?
    let department: String?
    let salaryValueText: String?
    let postedDate: String?

    enum CodingKeys: String, CodingKey {
        case slug
        case reqId = "req_id"
        case title
        case description
        case locationName = "location_name"
        case city
        case state
        case country
        case locationType = "location_type"
        case categories
        case department
        case salaryValueText = "salary_value"
        case postedDate = "posted_date"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        slug = try c.decode(String.self, forKey: .slug)
        reqId = try c.decodeIfPresent(String.self, forKey: .reqId)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        description = try c.decodeIfPresent(String.self, forKey: .description)
        locationName = try c.decodeIfPresent(String.self, forKey: .locationName)
        city = try c.decodeIfPresent(String.self, forKey: .city)
        state = try c.decodeIfPresent(String.self, forKey: .state)
        country = try c.decodeIfPresent(String.self, forKey: .country)
        locationType = try c.decodeIfPresent(String.self, forKey: .locationType)
        categories = Self.decodeCategories(from: c)
        department = try c.decodeIfPresent(String.self, forKey: .department)
        postedDate = try c.decodeIfPresent(String.self, forKey: .postedDate)
        if let text = try? c.decode(String.self, forKey: .salaryValueText) {
            salaryValueText = text
        } else if let number = try? c.decode(Int.self, forKey: .salaryValueText), number > 0 {
            salaryValueText = String(number)
        } else if let number = try? c.decode(Double.self, forKey: .salaryValueText), number > 0 {
            salaryValueText = String(number)
        } else {
            salaryValueText = nil
        }
    }

    private static func decodeCategories(from container: KeyedDecodingContainer<CodingKeys>) -> [String]? {
        if let names = try? container.decode([String].self, forKey: .categories) {
            return names.isEmpty ? nil : names
        }
        if let objects = try? container.decode([JibeCategory].self, forKey: .categories) {
            let names = objects.map(\.name).filter { !$0.isEmpty }
            return names.isEmpty ? nil : names
        }
        return nil
    }
}

private struct JibeCategory: Decodable {
    let name: String
}
