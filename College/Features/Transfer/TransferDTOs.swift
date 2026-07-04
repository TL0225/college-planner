// TransferDTOs.swift
// Feature: Transfer
// Purpose: Transfer Database — transport/value types for sources, evaluation, and impact.
// Data: CollegePersistence / TransferRepository when applicable.

import Foundation

/// Portable representation of a single source→target equivalency.
/// Used by source engines, community import/export, and repository upserts.
struct TransferEquivalencyDTO: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var sourceSchoolID: String
    var sourceSchoolName: String
    var sourceCourseCode: String
    var sourceCourseTitle: String?
    var sourceCredits: Int
    var targetSchoolID: String
    var targetSchoolName: String
    var targetCourseCode: String
    var targetCourseTitle: String?
    var targetCredits: Int
    var equivalencyKind: TransferEquivalencyKind
    var degreeLevel: String
    var sourceTier: TransferSourceTier
    var sourceKind: TransferSourceKind
    var externalID: String
    var sourceURL: String?
    var effectiveTerm: String?
    var verificationStatus: TransferVerificationStatus
    var notes: String?
    var submittedAt: Date
    var lastVerifiedAt: Date?

    init(
        id: UUID = UUID(),
        sourceSchoolID: String,
        sourceSchoolName: String,
        sourceCourseCode: String,
        sourceCourseTitle: String? = nil,
        sourceCredits: Int,
        targetSchoolID: String,
        targetSchoolName: String,
        targetCourseCode: String,
        targetCourseTitle: String? = nil,
        targetCredits: Int,
        equivalencyKind: TransferEquivalencyKind,
        degreeLevel: String,
        sourceTier: TransferSourceTier,
        sourceKind: TransferSourceKind,
        externalID: String,
        sourceURL: String? = nil,
        effectiveTerm: String? = nil,
        verificationStatus: TransferVerificationStatus = .unverified,
        notes: String? = nil,
        submittedAt: Date = .now,
        lastVerifiedAt: Date? = nil
    ) {
        self.id = id
        self.sourceSchoolID = sourceSchoolID
        self.sourceSchoolName = sourceSchoolName
        self.sourceCourseCode = sourceCourseCode
        self.sourceCourseTitle = sourceCourseTitle
        self.sourceCredits = sourceCredits
        self.targetSchoolID = targetSchoolID
        self.targetSchoolName = targetSchoolName
        self.targetCourseCode = targetCourseCode
        self.targetCourseTitle = targetCourseTitle
        self.targetCredits = targetCredits
        self.equivalencyKind = equivalencyKind
        self.degreeLevel = degreeLevel
        self.sourceTier = sourceTier
        self.sourceKind = sourceKind
        self.externalID = externalID
        self.sourceURL = sourceURL
        self.effectiveTerm = effectiveTerm
        self.verificationStatus = verificationStatus
        self.notes = notes
        self.submittedAt = submittedAt
        self.lastVerifiedAt = lastVerifiedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case sourceSchoolID = "source_school_id"
        case sourceSchoolName = "source_school_name"
        case sourceCourseCode = "source_course_code"
        case sourceCourseTitle = "source_course_title"
        case sourceCredits = "source_credits"
        case targetSchoolID = "target_school_id"
        case targetSchoolName = "target_school_name"
        case targetCourseCode = "target_course_code"
        case targetCourseTitle = "target_course_title"
        case targetCredits = "target_credits"
        case equivalencyKind = "equivalency_kind"
        case degreeLevel = "degree_level"
        case sourceTier = "source_tier"
        case sourceKind = "source_kind"
        case externalID = "external_id"
        case sourceURL = "source_url"
        case effectiveTerm = "effective_term"
        case verificationStatus = "verification_status"
        case notes
        case submittedAt = "submitted_at"
        case lastVerifiedAt = "last_verified_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        sourceSchoolID = try c.decode(String.self, forKey: .sourceSchoolID)
        sourceSchoolName = try c.decode(String.self, forKey: .sourceSchoolName)
        sourceCourseCode = try c.decode(String.self, forKey: .sourceCourseCode)
        sourceCourseTitle = try? c.decodeIfPresent(String.self, forKey: .sourceCourseTitle)
        sourceCredits = (try? c.decode(Int.self, forKey: .sourceCredits)) ?? 0
        targetSchoolID = try c.decode(String.self, forKey: .targetSchoolID)
        targetSchoolName = try c.decode(String.self, forKey: .targetSchoolName)
        targetCourseCode = try c.decode(String.self, forKey: .targetCourseCode)
        targetCourseTitle = try? c.decodeIfPresent(String.self, forKey: .targetCourseTitle)
        targetCredits = (try? c.decode(Int.self, forKey: .targetCredits)) ?? 0
        equivalencyKind = (try? c.decode(TransferEquivalencyKind.self, forKey: .equivalencyKind)) ?? .direct
        degreeLevel = (try? c.decode(String.self, forKey: .degreeLevel)) ?? "undergraduate"
        sourceTier = (try? c.decode(TransferSourceTier.self, forKey: .sourceTier)) ?? .community
        sourceKind = (try? c.decode(TransferSourceKind.self, forKey: .sourceKind)) ?? .communityImport
        externalID = (try? c.decode(String.self, forKey: .externalID)) ?? ""
        sourceURL = try? c.decodeIfPresent(String.self, forKey: .sourceURL)
        effectiveTerm = try? c.decodeIfPresent(String.self, forKey: .effectiveTerm)
        verificationStatus = (try? c.decode(TransferVerificationStatus.self, forKey: .verificationStatus)) ?? .unverified
        notes = try? c.decodeIfPresent(String.self, forKey: .notes)
        submittedAt = (try? c.decode(Date.self, forKey: .submittedAt)) ?? .now
        lastVerifiedAt = try? c.decodeIfPresent(Date.self, forKey: .lastVerifiedAt)
    }
}

/// Request describing what an evaluation/refresh pass should cover.
struct TransferEvaluationInput: Hashable, Sendable {
    var sourceSchoolID: String
    var sourceSchoolName: String
    var targetSchoolID: String
    var targetSchoolName: String
    var degreeLevel: String
    var mode: TransferSourceMode

    init(
        sourceSchoolID: String,
        sourceSchoolName: String,
        targetSchoolID: String,
        targetSchoolName: String,
        degreeLevel: String = "undergraduate",
        mode: TransferSourceMode = .fixture
    ) {
        self.sourceSchoolID = sourceSchoolID
        self.sourceSchoolName = sourceSchoolName
        self.targetSchoolID = targetSchoolID
        self.targetSchoolName = targetSchoolName
        self.degreeLevel = degreeLevel
        self.mode = mode
    }
}

/// A resolved, confidence-scored course mapping ready for presentation.
struct TransferCourseResult: Identifiable, Hashable, Sendable {
    var id: UUID
    var dedupeKey: String
    var sourceCourseCode: String
    var sourceCourseTitle: String?
    var sourceCredits: Int
    var targetCourseCode: String
    var targetCourseTitle: String?
    var targetCredits: Int
    var equivalencyKind: TransferEquivalencyKind
    var verificationStatus: TransferVerificationStatus
    var confidence: Int
    var sourceCount: Int
    var bestTier: TransferSourceTier
    var hasValidatedProof: Bool
    var evidence: [TransferEvidenceDTO]

    init(
        id: UUID = UUID(),
        dedupeKey: String,
        sourceCourseCode: String,
        sourceCourseTitle: String? = nil,
        sourceCredits: Int,
        targetCourseCode: String,
        targetCourseTitle: String? = nil,
        targetCredits: Int,
        equivalencyKind: TransferEquivalencyKind,
        verificationStatus: TransferVerificationStatus,
        confidence: Int,
        sourceCount: Int,
        bestTier: TransferSourceTier,
        hasValidatedProof: Bool,
        evidence: [TransferEvidenceDTO]
    ) {
        self.id = id
        self.dedupeKey = dedupeKey
        self.sourceCourseCode = sourceCourseCode
        self.sourceCourseTitle = sourceCourseTitle
        self.sourceCredits = sourceCredits
        self.targetCourseCode = targetCourseCode
        self.targetCourseTitle = targetCourseTitle
        self.targetCredits = targetCredits
        self.equivalencyKind = equivalencyKind
        self.verificationStatus = verificationStatus
        self.confidence = confidence
        self.sourceCount = sourceCount
        self.bestTier = bestTier
        self.hasValidatedProof = hasValidatedProof
        self.evidence = evidence
    }
}

/// A single provenance record backing a `TransferCourseResult`.
struct TransferEvidenceDTO: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var sourceKind: TransferSourceKind
    var sourceTier: TransferSourceTier
    var externalID: String
    var sourceURL: String?
    var effectiveTerm: String?
    var capturedAt: Date

    init(
        id: UUID = UUID(),
        sourceKind: TransferSourceKind,
        sourceTier: TransferSourceTier,
        externalID: String,
        sourceURL: String? = nil,
        effectiveTerm: String? = nil,
        capturedAt: Date = .now
    ) {
        self.id = id
        self.sourceKind = sourceKind
        self.sourceTier = sourceTier
        self.externalID = externalID
        self.sourceURL = sourceURL
        self.effectiveTerm = effectiveTerm
        self.capturedAt = capturedAt
    }
}

/// Outcome of validating a transcript / articulation proof PDF.
struct TransferProofValidationResult: Codable, Hashable, Sendable {
    var isAcceptable: Bool
    var score: Double
    var detectedUniversityName: String?
    var hasRegistrarHeader: Bool
    var signatureDetected: Bool
    var pdfProducer: String?
    var pdfCreationDate: Date?
    var textExtractionMethod: TransferTextExtractionMethod
    var notes: [String]

    init(
        isAcceptable: Bool,
        score: Double,
        detectedUniversityName: String? = nil,
        hasRegistrarHeader: Bool = false,
        signatureDetected: Bool = false,
        pdfProducer: String? = nil,
        pdfCreationDate: Date? = nil,
        textExtractionMethod: TransferTextExtractionMethod = .none,
        notes: [String] = []
    ) {
        self.isAcceptable = isAcceptable
        self.score = score
        self.detectedUniversityName = detectedUniversityName
        self.hasRegistrarHeader = hasRegistrarHeader
        self.signatureDetected = signatureDetected
        self.pdfProducer = pdfProducer
        self.pdfCreationDate = pdfCreationDate
        self.textExtractionMethod = textExtractionMethod
        self.notes = notes
    }
}

/// One row describing how a transfer result affects a degree requirement.
struct TransferRequirementsImpactRow: Identifiable, Hashable, Sendable {
    var id: UUID
    var requirementCategory: String
    var requirementDisplayTitle: String
    var targetCourseCode: String
    var targetCourseTitle: String?
    var matchedSourceCourseCode: String?
    var creditsApplied: Int
    var bucket: TransferCourseScheduleBucket
    var confidence: Int
    var alreadySatisfied: Bool

    init(
        id: UUID = UUID(),
        requirementCategory: String,
        requirementDisplayTitle: String,
        targetCourseCode: String,
        targetCourseTitle: String? = nil,
        matchedSourceCourseCode: String? = nil,
        creditsApplied: Int,
        bucket: TransferCourseScheduleBucket,
        confidence: Int,
        alreadySatisfied: Bool
    ) {
        self.id = id
        self.requirementCategory = requirementCategory
        self.requirementDisplayTitle = requirementDisplayTitle
        self.targetCourseCode = targetCourseCode
        self.targetCourseTitle = targetCourseTitle
        self.matchedSourceCourseCode = matchedSourceCourseCode
        self.creditsApplied = creditsApplied
        self.bucket = bucket
        self.confidence = confidence
        self.alreadySatisfied = alreadySatisfied
    }
}

/// Envelope used for community dataset import/export payloads.
struct TransferCommunityPayload: Codable, Hashable, Sendable {
    var version: Int
    var generatedAt: Date
    var equivalencies: [TransferEquivalencyDTO]

    init(version: Int = 1, generatedAt: Date = .now, equivalencies: [TransferEquivalencyDTO]) {
        self.version = version
        self.generatedAt = generatedAt
        self.equivalencies = equivalencies
    }

    enum CodingKeys: String, CodingKey {
        case version
        case generatedAt = "generated_at"
        case equivalencies
    }
}
