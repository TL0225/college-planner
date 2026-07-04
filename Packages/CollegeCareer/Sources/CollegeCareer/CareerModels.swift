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

public enum CourseGapTiming: String, Codable, Sendable {
    case current
    case upcoming
    case future
}

public struct CareerCourseSkillGap: Codable, Sendable, Equatable {
    public var skill: String
    public var courseCode: String?
    public var courseTitle: String?
    public var timing: CourseGapTiming?

    public init(skill: String, courseCode: String? = nil, courseTitle: String? = nil, timing: CourseGapTiming? = nil) {
        self.skill = skill
        self.courseCode = courseCode
        self.courseTitle = courseTitle
        self.timing = timing
    }
}

public struct SkillGapEntry: Codable, Sendable, Equatable {
    public var skill: String
    public var status: String
    public var evidenceBullet: String?
    public var recencyNote: String?

    public init(skill: String, status: String, evidenceBullet: String? = nil, recencyNote: String? = nil) {
        self.skill = skill
        self.status = status
        self.evidenceBullet = evidenceBullet
        self.recencyNote = recencyNote
    }
}

public struct CareerResumeCompareResult: Codable, Sendable {
    public var matchingSkills: [String]
    public var missingKeywords: [String]
    public var tip: String
    public var overallScore: Int?
    public var keywordScore: Int?
    public var semanticScore: Int?
    public var experienceScore: Int?
    public var formattingScore: Int?
    public var courseSkillGaps: [CareerCourseSkillGap]?
    public var portalTips: [String]?
    public var experienceGapExplanation: String?
    public var transferableSkillsNoted: [String]?

    public init(
        matchingSkills: [String],
        missingKeywords: [String],
        tip: String,
        overallScore: Int? = nil,
        keywordScore: Int? = nil,
        semanticScore: Int? = nil,
        experienceScore: Int? = nil,
        formattingScore: Int? = nil,
        courseSkillGaps: [CareerCourseSkillGap]? = nil,
        portalTips: [String]? = nil,
        experienceGapExplanation: String? = nil,
        transferableSkillsNoted: [String]? = nil
    ) {
        self.matchingSkills = matchingSkills
        self.missingKeywords = missingKeywords
        self.tip = tip
        self.overallScore = overallScore
        self.keywordScore = keywordScore
        self.semanticScore = semanticScore
        self.experienceScore = experienceScore
        self.formattingScore = formattingScore
        self.courseSkillGaps = courseSkillGaps
        self.portalTips = portalTips
        self.experienceGapExplanation = experienceGapExplanation
        self.transferableSkillsNoted = transferableSkillsNoted
    }
}

public struct CareerResumeMatchRow: Codable, Sendable, Identifiable, Equatable {
    public var id: UUID
    public var resumeDocumentID: UUID
    public var displayName: String
    public var overallScore: Int
    public var keywordScore: Int
    public var semanticScore: Int
    public var experienceScore: Int
    public var matchingSkills: [String]
    public var missingKeywords: [String]
    public var tip: String
    public var isRecommended: Bool
    public var scoreDelta: Int?
    public var portalTips: [String]?
    public var courseSkillGaps: [CareerCourseSkillGap]?
    public var platformProfileName: String?
    public var experienceGapNote: String?
    public var candidateYearsMonths: String?
    public var requiredYearsMin: Int?
    public var requiredYearsMax: Int?
    public var transferableScore: Int
    public var achievementScore: Int
    public var trajectoryNote: String?
    public var seniorityAlignmentNote: String?
    public var skillsGapTaxonomy: [SkillGapEntry]?
    public var roleFitScore: Int
    public var roleMismatchNote: String?
    public var resumeTargetRole: String?

    public init(
        id: UUID = UUID(),
        resumeDocumentID: UUID,
        displayName: String,
        overallScore: Int,
        keywordScore: Int,
        semanticScore: Int,
        experienceScore: Int,
        matchingSkills: [String],
        missingKeywords: [String],
        tip: String,
        isRecommended: Bool = false,
        scoreDelta: Int? = nil,
        portalTips: [String]? = nil,
        courseSkillGaps: [CareerCourseSkillGap]? = nil,
        platformProfileName: String? = nil,
        experienceGapNote: String? = nil,
        candidateYearsMonths: String? = nil,
        requiredYearsMin: Int? = nil,
        requiredYearsMax: Int? = nil,
        transferableScore: Int = 0,
        achievementScore: Int = 0,
        trajectoryNote: String? = nil,
        seniorityAlignmentNote: String? = nil,
        skillsGapTaxonomy: [SkillGapEntry]? = nil,
        roleFitScore: Int = 50,
        roleMismatchNote: String? = nil,
        resumeTargetRole: String? = nil
    ) {
        self.id = id
        self.resumeDocumentID = resumeDocumentID
        self.displayName = displayName
        self.overallScore = overallScore
        self.keywordScore = keywordScore
        self.semanticScore = semanticScore
        self.experienceScore = experienceScore
        self.matchingSkills = matchingSkills
        self.missingKeywords = missingKeywords
        self.tip = tip
        self.isRecommended = isRecommended
        self.scoreDelta = scoreDelta
        self.portalTips = portalTips
        self.courseSkillGaps = courseSkillGaps
        self.platformProfileName = platformProfileName
        self.experienceGapNote = experienceGapNote
        self.candidateYearsMonths = candidateYearsMonths
        self.requiredYearsMin = requiredYearsMin
        self.requiredYearsMax = requiredYearsMax
        self.transferableScore = transferableScore
        self.achievementScore = achievementScore
        self.trajectoryNote = trajectoryNote
        self.seniorityAlignmentNote = seniorityAlignmentNote
        self.skillsGapTaxonomy = skillsGapTaxonomy
        self.roleFitScore = roleFitScore
        self.roleMismatchNote = roleMismatchNote
        self.resumeTargetRole = resumeTargetRole
    }
}

public struct CareerResumeSuggestion: Codable, Sendable, Identifiable, Equatable {
    public enum SuggestionType: String, Codable, Sendable {
        case actionVerbUpgrade
        case keywordInjection
        case clarification
        case conciseness
        case starExpansion
        case metricPrompt
    }

    public enum ConfidenceTier: String, Codable, Sendable {
        case safe
        case verify
    }

    public var id: UUID
    public var entryHeading: String
    public var originalBullet: String
    public var proposedBullet: String
    public var rationale: String
    public var type: SuggestionType
    public var tier: ConfidenceTier
    public var scoreDeltaEstimate: Int?

    public init(
        id: UUID = UUID(),
        entryHeading: String,
        originalBullet: String,
        proposedBullet: String,
        rationale: String,
        type: SuggestionType,
        tier: ConfidenceTier,
        scoreDeltaEstimate: Int? = nil
    ) {
        self.id = id
        self.entryHeading = entryHeading
        self.originalBullet = originalBullet
        self.proposedBullet = proposedBullet
        self.rationale = rationale
        self.type = type
        self.tier = tier
        self.scoreDeltaEstimate = scoreDeltaEstimate
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

