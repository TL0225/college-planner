// CareerModels.swift
// Feature: Career
// Purpose: Career module — CareerOfferCompensationPackage.
// Data: CollegePersistence / repositories when applicable.

import Foundation

public enum CareerApplicationStatus: String, CaseIterable, Codable, Sendable {
    case interested
    case applied
    case interviewing
    case offer
    case rejected
    case accepted

    public var displayName: String {
        switch self {
        case .interested: return "Interested"
        case .applied: return "Applied"
        case .interviewing: return "Interviewing"
        case .offer: return "Offer"
        case .rejected: return "Rejected"
        case .accepted: return "Accepted"
        }
    }
}

/// Interview pipeline step persisted in application `provenanceJSON` for the Kanban inspector.
public enum CareerSalaryTextParse {
    /// Parses common human-entered salary strings (e.g. `150000`, `$150k`, `85k USD /yr`) into an approximate integer annual USD amount when unambiguous.
    public static func approximateAnnualUSD(from raw: String?) -> Int? {
        guard let raw else { return nil }
        var s = raw
            .lowercased()
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: "usd", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        // Reject ranged blobs like "120-140k" where a single scalar is ambiguous.
        if s.range(of: #"\d\s*-\s*\d"#, options: .regularExpression) != nil { return nil }

        var multiplier = 1.0
        if let range = s.range(of: "/yr") {
            s.removeSubrange(range)
            s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if s.hasSuffix("k") {
            multiplier *= 1_000
            s.removeLast()
        } else if s.hasSuffix("m") {
            multiplier *= 1_000_000
            s.removeLast()
        }
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, let scalar = Double(s) else { return nil }
        guard scalar.isFinite, scalar >= 0 else { return nil }
        return Int((scalar * multiplier).rounded())
    }
}

public struct CareerOfferCompensationPackage: Equatable, Sendable {
    public var bonusText: String
    public var signingText: String
    public var equityText: String

    public init(bonusText: String, signingText: String, equityText: String) {
        self.bonusText = bonusText
        self.signingText = signingText
        self.equityText = equityText
    }

    public static let empty = CareerOfferCompensationPackage(bonusText: "", signingText: "", equityText: "")
}

enum CareerInterviewPipelineStage: String, CaseIterable, Codable {
    case hr
    case technical
    case finalInterview = "final"

    public var displayTitle: String {
        switch self {
        case .hr: return "HR"
        case .technical: return "Technical"
        case .finalInterview: return "Final"
        }
    }
}

public struct CareerResumeCompareResult: Codable, Sendable {
    public var matchingSkills: [String]
    public var missingKeywords: [String]
    public var tip: String

    public init(matchingSkills: [String], missingKeywords: [String], tip: String) {
        self.matchingSkills = matchingSkills
        self.missingKeywords = missingKeywords
        self.tip = tip
    }
}

public struct CareerIngestPayload: Codable, Sendable {
    public let requestId: UUID
    public let sourceURL: String
    public let rawText: String
    public let createdAt: Date

    public init(requestId: UUID, sourceURL: String, rawText: String, createdAt: Date) {
        self.requestId = requestId
        self.sourceURL = sourceURL
        self.rawText = rawText
        self.createdAt = createdAt
    }
}

public struct CareerParseResult: Codable, Sendable {
    public let requestId: UUID
    public let company: String
    public let title: String
    public let baseSalary: String
    public let location: String
    public let keywords: [String]
    public let confidence: Double
    public let jobDescription: String

    public init(
        requestId: UUID,
        company: String,
        title: String,
        baseSalary: String,
        location: String,
        keywords: [String],
        confidence: Double,
        jobDescription: String
    ) {
        self.requestId = requestId
        self.company = company
        self.title = title
        self.baseSalary = baseSalary
        self.location = location
        self.keywords = keywords
        self.confidence = confidence
        self.jobDescription = jobDescription
    }
}

public struct CareerSaveRequest: Codable, Sendable {
    public let requestId: UUID
    public let company: String
    public let title: String
    public let baseSalary: String
    public let location: String
    public let keywords: [String]
    public let jobDescription: String
    public let postingURL: String
    public let applicationDeadline: Date

    public init(
        requestId: UUID,
        company: String,
        title: String,
        baseSalary: String,
        location: String,
        keywords: [String],
        jobDescription: String,
        postingURL: String,
        applicationDeadline: Date
    ) {
        self.requestId = requestId
        self.company = company
        self.title = title
        self.baseSalary = baseSalary
        self.location = location
        self.keywords = keywords
        self.jobDescription = jobDescription
        self.postingURL = postingURL
        self.applicationDeadline = applicationDeadline
    }
}

