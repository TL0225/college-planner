// TransferModels.swift
// Feature: Transfer
// Purpose: Transfer Database — value enums shared across sources, confidence, and storage.
// Data: CollegePersistence / TransferRepository when applicable.

import Foundation

/// Provenance ranking for a transfer equivalency. Higher tiers seed higher base confidence.
enum TransferSourceTier: String, Codable, CaseIterable, Sendable {
    case official
    case communityVerified = "community_verified"
    case community
    case manual

    /// Coarse confidence floor (0...100) contributed purely by provenance.
    var baseConfidence: Int {
        switch self {
        case .official: return 70
        case .communityVerified: return 55
        case .community: return 35
        case .manual: return 25
        }
    }

    /// Sort weight used when multiple tiers describe the same pairing (higher wins).
    var rank: Int {
        switch self {
        case .official: return 3
        case .communityVerified: return 2
        case .community: return 1
        case .manual: return 0
        }
    }
}

/// The concrete origin system an equivalency was harvested from.
enum TransferSourceKind: String, Codable, CaseIterable, Sendable {
    case assist
    case tesPublicView = "tes_public_view"
    case banner8Articulation = "banner8_articulation"
    case banner9SSB = "banner9_ssb"
    case communityImport = "community_import"
    case githubDataset = "github_dataset"
    case manualEntry = "manual_entry"

    var tier: TransferSourceTier {
        switch self {
        case .assist, .tesPublicView, .banner8Articulation, .banner9SSB:
            return .official
        case .githubDataset, .communityImport:
            return .community
        case .manualEntry:
            return .manual
        }
    }

    var displayName: String {
        switch self {
        case .assist: return "ASSIST.org"
        case .tesPublicView: return "Transfer Evaluation System"
        case .banner8Articulation: return "Banner 8 Articulation"
        case .banner9SSB: return "Banner 9 Self-Service"
        case .communityImport: return "Community Import"
        case .githubDataset: return "Shared Dataset"
        case .manualEntry: return "Manual Entry"
        }
    }
}

/// How a source course maps onto a target course.
enum TransferEquivalencyKind: String, Codable, CaseIterable, Sendable {
    case direct
    case partial
    case elective
    case conditional
    case notTransferable = "not_transferable"

    var displayName: String {
        switch self {
        case .direct: return "Direct Equivalent"
        case .partial: return "Partial Credit"
        case .elective: return "Elective Credit"
        case .conditional: return "Conditional"
        case .notTransferable: return "Not Transferable"
        }
    }

    /// Multiplier (0...1) applied to confidence; weaker mappings carry less certainty value.
    var confidenceWeight: Double {
        switch self {
        case .direct: return 1.0
        case .partial: return 0.85
        case .elective: return 0.7
        case .conditional: return 0.6
        case .notTransferable: return 0.5
        }
    }
}

/// Review lifecycle for a stored equivalency.
enum TransferVerificationStatus: String, Codable, CaseIterable, Sendable {
    case unverified
    case pendingReview = "pending_review"
    case verified
    case rejected
    case expired

    var displayName: String {
        switch self {
        case .unverified: return "Unverified"
        case .pendingReview: return "Pending Review"
        case .verified: return "Verified"
        case .rejected: return "Rejected"
        case .expired: return "Expired"
        }
    }
}

/// Strategy that produced the text used to validate a proof document.
enum TransferTextExtractionMethod: String, Codable, CaseIterable, Sendable {
    case nativePDFText = "native_pdf_text"
    case ocr
    case manual
    case none
}

/// The official routing leg chosen by `OfficialTransferSourceRouter`.
enum TransferOfficialRouteKind: String, Codable, CaseIterable, Sendable {
    case aggregator
    case tesPublicView = "tes_public_view"
    case banner8Articulation = "banner8_articulation"
    case banner9SSB = "banner9_ssb"

    var sourceKind: TransferSourceKind {
        switch self {
        case .aggregator: return .assist
        case .tesPublicView: return .tesPublicView
        case .banner8Articulation: return .banner8Articulation
        case .banner9SSB: return .banner9SSB
        }
    }
}

/// Buckets used when projecting a learner's plan courses for impact analysis.
enum TransferCourseScheduleBucket: String, Codable, CaseIterable, Sendable {
    case completed
    case inProgress = "in_progress"
    case planned
    case unscheduled

    var displayName: String {
        switch self {
        case .completed: return "Completed"
        case .inProgress: return "In Progress"
        case .planned: return "Planned"
        case .unscheduled: return "Unscheduled"
        }
    }
}

/// Whether engines should read bundled fixtures or perform live, human-paced requests.
enum TransferSourceMode: String, Codable, CaseIterable, Sendable {
    case fixture
    case live
}

/// Coordinator-facing status of an official refresh pass.
enum TransferOfficialRefreshStatus: String, Codable, CaseIterable, Sendable {
    case idle
    case running
    case success
    case partial
    case failed
    case throttled
}

/// Errors surfaced across the transfer subsystem.
enum TransferError: LocalizedError, Equatable {
    case missingSourceSchool
    case missingTargetSchool
    case unsupportedSource(TransferSourceKind)
    case fixtureNotFound(String)
    case emptyResult
    case throttled
    case network(String)
    case parsing(String)
    case proofUnreadable
    case validationFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingSourceSchool: return "A source school is required."
        case .missingTargetSchool: return "A target school is required."
        case .unsupportedSource(let kind): return "Source \(kind.displayName) is not supported here."
        case .fixtureNotFound(let name): return "Bundled fixture \(name) was not found."
        case .emptyResult: return "No transfer equivalencies were returned."
        case .throttled: return "Requests are being paced to respect the source. Try again shortly."
        case .network(let message): return "Network error: \(message)"
        case .parsing(let message): return "Could not parse source response: \(message)"
        case .proofUnreadable: return "The proof document could not be read."
        case .validationFailed(let message): return "Proof validation failed: \(message)"
        }
    }
}
