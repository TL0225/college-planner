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

    var displayMessage: String {
        switch self {
        case .badURL:
            return "Careers URL format not recognized. Check Settings."
        case .httpError(let code):
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

    var listJobsURL: URL { apiBase.appendingPathComponent("jobs") }

    func publicJobURL(externalPath: String) -> String? {
        var base = careersURL.absoluteString
        while base.hasSuffix("/") { base.removeLast() }
        let path = externalPath.hasPrefix("/") ? externalPath : "/" + externalPath
        return base + path
    }

    func detailURL(externalPath: String) -> URL? {
        let trimmed = externalPath.hasPrefix("/") ? String(externalPath.dropFirst()) : externalPath
        return apiBase.appendingPathComponent(trimmed)
    }
}

// MARK: - List response (stable)

struct WorkdayJobListResponse: Codable, Sendable {
    let total: Int
    let jobPostings: [WorkdayScrapedJob]
    let facets: [WorkdayFacet]?
}

struct WorkdayFacet: Codable, Sendable {
    let facetParameter: String
    let descriptor: String?
    let values: [WorkdayFacetValue]?
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
