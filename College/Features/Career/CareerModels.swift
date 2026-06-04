// CareerModels.swift
// Feature: Career
// Purpose: Career module — CareerOfferCompensationPackage.
// Data: CollegePersistence / repositories when applicable.

import Foundation

enum CareerApplicationStatus: String, CaseIterable, Codable {
    case interested
    case applied
    case interviewing
    case offer
    case rejected
    case accepted

    var displayName: String {
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
enum CareerSalaryTextParse {
    /// Parses common human-entered salary strings (e.g. `150000`, `$150k`, `85k USD /yr`) into an approximate integer annual USD amount when unambiguous.
    static func approximateAnnualUSD(from raw: String?) -> Int? {
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

struct CareerOfferCompensationPackage: Equatable, Sendable {
    var bonusText: String
    var signingText: String
    var equityText: String

    static let empty = CareerOfferCompensationPackage(bonusText: "", signingText: "", equityText: "")
}

enum CareerInterviewPipelineStage: String, CaseIterable, Codable {
    case hr
    case technical
    case finalInterview = "final"

    var displayTitle: String {
        switch self {
        case .hr: return "HR"
        case .technical: return "Technical"
        case .finalInterview: return "Final"
        }
    }
}

struct CareerResumeCompareResult: Codable, Sendable {
    var matchingSkills: [String]
    var missingKeywords: [String]
    var tip: String
}

struct CareerIngestPayload: Codable, Sendable {
    let requestId: UUID
    let sourceURL: String
    let rawText: String
    let createdAt: Date
}

struct CareerParseResult: Codable, Sendable {
    let requestId: UUID
    let company: String
    let title: String
    let baseSalary: String
    let location: String
    let keywords: [String]
    let confidence: Double
    let jobDescription: String
}

struct CareerSaveRequest: Codable, Sendable {
    let requestId: UUID
    let company: String
    let title: String
    let baseSalary: String
    let location: String
    let keywords: [String]
    let jobDescription: String
    let postingURL: String
    let applicationDeadline: Date
}

enum CareerFeaturePreloadRegistration {
    @MainActor
    static func register() {
        LaunchPreloadCoordinator.registerFeaturePreload(
            .init(
                id: "career",
                title: "Career data",
                criticality: .bestEffort,
                timeoutSeconds: 0.5,
                retryLimit: 0,
                run: { context, onProgress, onDetail in
                    let count = await context.collegePersistence.prefetchCareerApplicationsForLaunch()
                    onDetail("Loaded \(count) applications")
                    onProgress(1)
                }
            )
        )
    }
}
