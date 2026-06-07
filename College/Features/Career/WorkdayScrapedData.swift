// WorkdayScrapedData.swift
// Feature: Career
// Purpose: Career module — WorkdayAPIContext.
// Data: CollegePersistence / repositories when applicable.

import AppKit
import Foundation

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

    var listJobsURL: URL {
        var base = apiBase.absoluteString
        while base.hasSuffix("/") { base.removeLast() }
        return URL(string: base + "/jobs")!
    }

    func publicJobURL(externalPath: String) -> String? {
        var base = careersURL.absoluteString
        while base.hasSuffix("/") { base.removeLast() }
        let path = externalPath.hasPrefix("/") ? externalPath : "/" + externalPath
        return base + path
    }

    func detailURL(externalPath: String) -> URL? {
        let pathSuffix = externalPath.hasPrefix("/") ? externalPath : "/" + externalPath
        var base = apiBase.absoluteString
        while base.hasSuffix("/") { base.removeLast() }
        return URL(string: base + pathSuffix)
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
    static func decode(from data: Data) throws -> WorkdayJobListResponse {
        if data.isEmpty {
            throw WorkdayScraperError.decodingFailed("Empty response from Workday jobs API")
        }
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], object.isEmpty {
            throw WorkdayScraperError.decodingFailed(
                "Workday returned an empty JSON object — verify the board URL (e.g. https://insmed.wd5.myworkdayjobs.com/en-US/EXTERNAL) and network/VPN settings"
            )
        }
        if let apiError = try? JSONDecoder().decode(WorkdayAPIErrorBody.self, from: data),
           let code = apiError.errorCode?.trimmingCharacters(in: .whitespacesAndNewlines),
           !code.isEmpty,
           !data.contains("jobPostings".utf8) {
            let message = apiError.message?.trimmingCharacters(in: .whitespacesAndNewlines)
            let detail = (message?.isEmpty == false) ? message! : code
            throw WorkdayScraperError.decodingFailed("Workday API error: \(detail)")
        }
        do {
            return try JSONDecoder().decode(WorkdayJobListResponse.self, from: data)
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

    var salaryRangeText: String? {
        nil
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
            if !trimmed.isEmpty, !WorkdayPostingParsing.isAggregateLocationCount(trimmed) {
                return trimmed
            }
        }
        return nil
    }

    enum CodingKeys: String, CodingKey {
        case title, jobReqId, locationsText, location, jobDescription, timeType, remoteType
        case startDate, postedOn, workLocation, jobRequisitionLocation, additionalLocations
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
        if let strings = try container.decodeIfPresent([String].self, forKey: .additionalLocations) {
            additionalLocations = strings
        } else if let objects = try container.decodeIfPresent([WorkdayAdditionalLocation].self, forKey: .additionalLocations) {
            additionalLocations = objects.compactMap(\.location).filter { !$0.isEmpty }
        } else {
            additionalLocations = nil
        }
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
            return WorkdayHTMLText.plainText(fromHTML: html)
        }
        if let rich = try? container.decode(WorkdayRichText.self, forKey: .jobDescription) {
            return rich.flattenedPlainText()
        }
        return ""
    }
}

enum WorkdayHTMLText {
    /// Converts Workday HTML job descriptions to readable plain text.
    static func plainText(fromHTML html: String) -> String {
        let trimmed = html.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        if let data = trimmed.data(using: .utf8),
           let attributed = try? NSAttributedString(
               data: data,
               options: [
                   .documentType: NSAttributedString.DocumentType.html,
                   .characterEncoding: String.Encoding.utf8.rawValue,
               ],
               documentAttributes: nil
           ) {
            let text = attributed.string
                .replacingOccurrences(of: "\u{FFFC}", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { return text }
        }

        return stripTagsFallback(trimmed)
    }

    private static func stripTagsFallback(_ html: String) -> String {
        html
            .replacingOccurrences(of: "<br[^>]*>", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "</p>", with: "\n", options: .caseInsensitive)
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
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
