// OracleHCMScraper.swift
// Feature: Career
// Purpose: Career module — OracleListEnvelope.
// Data: CollegePersistence / repositories when applicable.

import Foundation

actor OracleHCMScraper: JobBoardScraper {
    static let shared = OracleHCMScraper()
    private let session = JobBoardHTTP.makeSession()

    func scrapeListings(
        for company: WorkdayCompanyConfigEntry,
        reportProgress: (@Sendable (Int, Int?) -> Void)?
    ) async throws -> [ScrapedJobListing] {
        let (base, siteNumber) = try await resolveContext(careersURL: company.careersURL)
        let applyBase = oracleApplyBaseURL(careersURL: company.careersURL, siteNumber: siteNumber)
        var all: [ScrapedJobListing] = []
        var offset = 0
        let limit = 100
        var totalJobs: Int?
        reportProgress?(0, nil)
        while offset < 50_000 {
            let finder = "findReqs;siteNumber=\(siteNumber),limit=\(limit),offset=\(offset)"
            var components = URLComponents(url: base.appendingPathComponent("hcmRestApi/resources/latest/recruitingCEJobRequisitions"), resolvingAgainstBaseURL: true)!
            components.queryItems = [
                URLQueryItem(name: "finder", value: finder),
                URLQueryItem(name: "expand", value: "requisitionList"),
                URLQueryItem(name: "onlyData", value: "true"),
            ]
            guard let url = components.url else { throw JobBoardScraperError.badURL }
            let (data, _) = try await JobBoardHTTP.get(url: url, session: session, headers: oracleHeaders)
            let decoded = try JSONDecoder().decode(OracleListEnvelope.self, from: data)
            guard let page = decoded.items?.first else { break }
            if totalJobs == nil { totalJobs = page.totalJobsCount }
            let items = page.requisitionList ?? []
            if items.isEmpty { break }
            for item in items {
                let id = item.id
                let applyURL = applyBase?.appendingPathComponent("job/\(id)").absoluteString
                all.append(ScrapedJobListing(
                    externalId: id,
                    externalPath: id,
                    title: item.title ?? "Untitled",
                    locationText: item.primaryLocation,
                    postedOn: item.postedDate,
                    applyURLString: applyURL,
                    jobTypeText: item.jobType,
                    timeType: item.jobSchedule,
                    listingHash: WorkdayListingHash.compute(title: item.title ?? "", locationsText: item.primaryLocation)
                ))
            }
            offset += items.count
            reportProgress?(offset, totalJobs)
            if let totalJobs, offset >= totalJobs { break }
        }
        reportProgress?(all.count, all.count)
        return all
    }

    func scrapeDetail(
        request: JobDetailScrapeRequest,
        company: WorkdayCompanyConfigEntry
    ) async throws -> ScrapedJobDetail {
        let (base, siteNumber) = try await resolveContext(careersURL: company.careersURL)
        guard !request.externalId.isEmpty else { throw JobBoardScraperError.badURL }
        let id = request.externalId
        var components = URLComponents(url: base.appendingPathComponent("hcmRestApi/resources/latest/recruitingCEJobRequisitionDetails"), resolvingAgainstBaseURL: true)!
        components.queryItems = [
            URLQueryItem(name: "finder", value: "ById;Id=\"\(id)\",siteNumber=\(siteNumber)"),
            URLQueryItem(name: "expand", value: "all"),
            URLQueryItem(name: "onlyData", value: "true"),
        ]
        guard let url = components.url else { throw JobBoardScraperError.badURL }
        let (data, _) = try await JobBoardHTTP.get(url: url, session: session, headers: oracleHeaders)
        let decoded = try JSONDecoder().decode(OracleDetailEnvelope.self, from: data)
        guard let detail = decoded.items?.first else {
            throw JobBoardScraperError.decodingFailed("No detail item")
        }
        let descHTML = detail.externalDescriptionStr ?? detail.shortDescriptionStr ?? ""
        let qualHTML = detail.externalQualificationsStr ?? ""
        let plain = JobBoardHTTP.htmlToPlain(descHTML)
        let req = JobBoardHTTP.htmlToPlain(qualHTML)
        return ScrapedJobDetail(
            title: detail.title ?? request.fallbackTitle,
            descriptionPlain: plain.isEmpty ? (request.cachedDescription ?? "") : plain,
            requirementsPlain: req.isEmpty ? nil : req,
            locationDisplay: detail.primaryLocation,
            filterLocations: detail.primaryLocation.map { [$0] } ?? [],
            postedAt: nil,
            postedOnDisplay: detail.postedDate,
            workModel: detail.workplaceType,
            jobTypeText: detail.jobType,
            timeType: detail.jobSchedule,
            salaryText: nil
        )
    }

    func logoURL(for company: WorkdayCompanyConfigEntry) -> URL? {
        guard let url = URL(string: company.careersURL) else { return nil }
        return URL(string: "https://\(url.host ?? "")/favicon.ico")
    }

    private var oracleHeaders: [String: String] {
        [
            "ora-irc-cx-userid": "00000000-0000-0000-0000-000000000000",
            "ora-irc-language": "en",
            "Content-Type": "application/vnd.oracle.adf.resourceitem+json;charset=utf-8",
        ]
    }

    private func resolveContext(careersURL: String) async throws -> (URL, String) {
        guard let url = URL(string: careersURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = url.host?.lowercased(),
              host.contains("oraclecloud.com")
        else { throw JobBoardScraperError.badURL }

        let base = URL(string: "https://\(host)/")!
        if let site = extractSiteNumber(from: careersURL) {
            return (base, site)
        }
        let (data, _) = try await JobBoardHTTP.get(url: url, session: session)
        guard let html = String(data: data, encoding: .utf8),
              let site = extractSiteNumber(from: html)
        else { throw JobBoardScraperError.decodingFailed("Could not find Oracle siteNumber") }
        return (base, site)
    }

    private func extractSiteNumber(from text: String) -> String? {
        let patterns = [
            #"/sites/(CX_\d+)"#,
            #"siteNumber\s*[:=]\s*['"]?(CX_\d+)['"]?"#,
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: text)
            else { continue }
            return String(text[range])
        }
        return nil
    }

    private func oracleApplyBaseURL(careersURL: String, siteNumber: String) -> URL? {
        guard let url = URL(string: careersURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = url.host
        else { return nil }
        let path = url.path
        if path.contains("/sites/\(siteNumber)") {
            var trimmed = path
            if let range = trimmed.range(of: "/job/") {
                trimmed = String(trimmed[..<range.lowerBound])
            } else if trimmed.hasSuffix("/jobs") {
                trimmed = String(trimmed.dropLast(5))
            }
            return URL(string: "https://\(host)\(trimmed)")
        }
        return URL(string: "https://\(host)/hcmUI/CandidateExperience/en/sites/\(siteNumber)")
    }
}

private struct OracleListEnvelope: Decodable {
    let items: [OracleListItem]?
}

private struct OracleListItem: Decodable {
    let requisitionList: [OracleRequisition]?
    let totalJobsCount: Int?

    enum CodingKeys: String, CodingKey {
        case requisitionList
        case totalJobsCount = "TotalJobsCount"
    }
}

private struct OracleRequisition: Decodable {
    let id: String
    let title: String?
    let postedDate: String?
    let primaryLocation: String?
    let workplaceType: String?
    let jobSchedule: String?
    let jobType: String?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case title = "Title"
        case postedDate = "PostedDate"
        case primaryLocation = "PrimaryLocation"
        case workplaceType = "WorkplaceType"
        case jobSchedule = "JobSchedule"
        case jobType = "JobType"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let s = try? c.decode(String.self, forKey: .id) {
            id = s
        } else if let n = try? c.decode(Int.self, forKey: .id) {
            id = String(n)
        } else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: c, debugDescription: "Missing Id")
        }
        title = try c.decodeIfPresent(String.self, forKey: .title)
        postedDate = try c.decodeIfPresent(String.self, forKey: .postedDate)
        primaryLocation = try c.decodeIfPresent(String.self, forKey: .primaryLocation)
        workplaceType = try c.decodeIfPresent(String.self, forKey: .workplaceType)
        jobSchedule = try c.decodeIfPresent(String.self, forKey: .jobSchedule)
        jobType = try c.decodeIfPresent(String.self, forKey: .jobType)
    }
}

private struct OracleDetailEnvelope: Decodable {
    let items: [OracleDetailItem]?
}

private struct OracleDetailItem: Decodable {
    let title: String?
    let postedDate: String?
    let primaryLocation: String?
    let workplaceType: String?
    let jobSchedule: String?
    let jobType: String?
    let shortDescriptionStr: String?
    let externalDescriptionStr: String?
    let externalQualificationsStr: String?

    enum CodingKeys: String, CodingKey {
        case title = "Title"
        case postedDate = "PostedDate"
        case primaryLocation = "PrimaryLocation"
        case workplaceType = "WorkplaceType"
        case jobSchedule = "JobSchedule"
        case jobType = "JobType"
        case shortDescriptionStr = "ShortDescriptionStr"
        case externalDescriptionStr = "ExternalDescriptionStr"
        case externalQualificationsStr = "ExternalQualificationsStr"
    }
}
