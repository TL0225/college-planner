// TransferConfidenceEngine.swift
// Feature: Transfer / Confidence
// Purpose: Transfer Database — deterministic confidence scoring for an equivalency group.
// Data: Pure value transforms over DTOs.

import Foundation

/// Inputs to a single confidence computation: all corroborating evidence for one dedupe key,
/// plus proof and override signals.
struct TransferConfidenceContext: Sendable {
    var group: [TransferEquivalencyDTO]
    var hasValidatedProof: Bool
    var proofScore: Double?
    var manualOverride: Int?
    var now: Date

    init(
        group: [TransferEquivalencyDTO],
        hasValidatedProof: Bool = false,
        proofScore: Double? = nil,
        manualOverride: Int? = nil,
        now: Date = .now
    ) {
        self.group = group
        self.hasValidatedProof = hasValidatedProof
        self.proofScore = proofScore
        self.manualOverride = manualOverride
        self.now = now
    }
}

/// Computes a 0...100 confidence score combining provenance, corroboration, mapping strength,
/// review status, proof, and recency. The formula is intentionally deterministic and explainable.
enum TransferConfidenceEngine {
    /// Maximum corroboration bonus (number of distinct agreeing sources beyond the first).
    static let maxCorroboratingSources = 3
    static let corroborationStep = 8.0

    static func score(_ context: TransferConfidenceContext) -> Int {
        // Manual overrides win outright.
        if let override = context.manualOverride {
            return clamp(override)
        }
        guard !context.group.isEmpty else { return 0 }

        let bestTier = context.group.map(\.sourceTier).max(by: { $0.rank < $1.rank }) ?? .community
        let bestStatus = context.group.map(\.verificationStatus).max(by: { statusRank($0) < statusRank($1) }) ?? .unverified
        let dominantKind = dominantEquivalencyKind(context.group)

        var score = Double(bestTier.baseConfidence)

        // Corroboration: distinct source systems agreeing on the same fact.
        let distinctSources = Set(context.group.map(\.sourceKind)).count
        let corroboration = min(max(distinctSources - 1, 0), maxCorroboratingSources)
        score += Double(corroboration) * corroborationStep

        // Review status adjustment.
        score += verificationAdjustment(bestStatus)

        // Validated proof bonus.
        if context.hasValidatedProof {
            score += (context.proofScore ?? 0.8).clampedUnit() * 15.0
        }

        // Mapping strength scaling.
        score *= dominantKind.confidenceWeight

        // Recency decay relative to the freshest verification timestamp.
        score *= recencyMultiplier(context: context)

        return clamp(Int(score.rounded()))
    }

    // MARK: - Components

    static func verificationAdjustment(_ status: TransferVerificationStatus) -> Double {
        switch status {
        case .verified: return 15
        case .pendingReview: return 5
        case .unverified: return 0
        case .expired: return -10
        case .rejected: return -40
        }
    }

    static func recencyMultiplier(context: TransferConfidenceContext) -> Double {
        let freshest = context.group.compactMap { $0.lastVerifiedAt ?? Optional($0.submittedAt) }.max()
        guard let freshest else { return 0.95 }
        let years = max(0, context.now.timeIntervalSince(freshest)) / (60 * 60 * 24 * 365)
        // Lose 5% per year, floored at 70%.
        return max(0.7, 1.0 - years * 0.05)
    }

    static func dominantEquivalencyKind(_ group: [TransferEquivalencyDTO]) -> TransferEquivalencyKind {
        var counts: [TransferEquivalencyKind: Int] = [:]
        for dto in group { counts[dto.equivalencyKind, default: 0] += 1 }
        // Prefer stronger mappings on ties (higher confidenceWeight).
        return counts.max(by: { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value < rhs.value }
            return lhs.key.confidenceWeight < rhs.key.confidenceWeight
        })?.key ?? .direct
    }

    private static func statusRank(_ status: TransferVerificationStatus) -> Int {
        switch status {
        case .verified: return 4
        case .pendingReview: return 3
        case .unverified: return 2
        case .expired: return 1
        case .rejected: return 0
        }
    }

    static func clamp(_ value: Int) -> Int { min(100, max(0, value)) }
}

private extension Double {
    func clampedUnit() -> Double { Swift.min(1.0, Swift.max(0.0, self)) }
}
