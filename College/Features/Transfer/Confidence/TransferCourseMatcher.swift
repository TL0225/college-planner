// TransferCourseMatcher.swift
// Feature: Transfer / Confidence
// Purpose: Transfer Database — groups raw equivalencies into scored, deduped course results.
// Data: Pure value transforms over DTOs.

import Foundation

/// Collapses many provenance rows into one scored `TransferCourseResult` per source→target fact.
enum TransferCourseMatcher {
    /// Per-equivalency proof signal supplied by the caller (e.g. from stored proof records).
    struct ProofSignal: Sendable {
        var hasValidatedProof: Bool
        var score: Double?
        static let none = ProofSignal(hasValidatedProof: false, score: nil)
    }

    /// Builds presentation-ready results, sorted by confidence (desc) then source code.
    static func results(
        from dtos: [TransferEquivalencyDTO],
        proofSignal: (TransferEquivalencyDTO) -> ProofSignal = { _ in .none },
        overrides: [String: Int] = [:],
        now: Date = .now
    ) -> [TransferCourseResult] {
        let grouped = Dictionary(grouping: dtos) { TransferNormalization.dedupeKey(for: $0) }

        var results: [TransferCourseResult] = []
        results.reserveCapacity(grouped.count)

        for (key, group) in grouped {
            guard let representative = group.max(by: { $0.sourceTier.rank < $1.sourceTier.rank }) else { continue }

            let proof = group.reduce(into: ProofSignal.none) { partial, dto in
                let signal = proofSignal(dto)
                if signal.hasValidatedProof {
                    partial.hasValidatedProof = true
                    partial.score = max(partial.score ?? 0, signal.score ?? 0)
                }
            }

            let context = TransferConfidenceContext(
                group: group,
                hasValidatedProof: proof.hasValidatedProof,
                proofScore: proof.score,
                manualOverride: overrides[key],
                now: now
            )
            let confidence = TransferConfidenceEngine.score(context)
            let bestStatus = group.map(\.verificationStatus)
                .max(by: { statusRank($0) < statusRank($1) }) ?? .unverified

            let evidence = group
                .map { dto in
                    TransferEvidenceDTO(
                        sourceKind: dto.sourceKind,
                        sourceTier: dto.sourceTier,
                        externalID: dto.externalID,
                        sourceURL: dto.sourceURL,
                        effectiveTerm: dto.effectiveTerm,
                        capturedAt: dto.lastVerifiedAt ?? dto.submittedAt
                    )
                }
                .sorted { $0.sourceTier.rank > $1.sourceTier.rank }

            results.append(
                TransferCourseResult(
                    dedupeKey: key,
                    sourceCourseCode: representative.sourceCourseCode,
                    sourceCourseTitle: representative.sourceCourseTitle,
                    sourceCredits: representative.sourceCredits,
                    targetCourseCode: representative.targetCourseCode,
                    targetCourseTitle: representative.targetCourseTitle,
                    targetCredits: representative.targetCredits,
                    equivalencyKind: TransferConfidenceEngine.dominantEquivalencyKind(group),
                    verificationStatus: bestStatus,
                    confidence: confidence,
                    sourceCount: Set(group.map(\.sourceKind)).count,
                    bestTier: representative.sourceTier,
                    hasValidatedProof: proof.hasValidatedProof,
                    evidence: evidence
                )
            )
        }

        return results.sorted { lhs, rhs in
            if lhs.confidence != rhs.confidence { return lhs.confidence > rhs.confidence }
            if lhs.sourceCourseCode != rhs.sourceCourseCode { return lhs.sourceCourseCode < rhs.sourceCourseCode }
            return lhs.targetCourseCode < rhs.targetCourseCode
        }
    }

    /// Returns results whose source course matches `sourceCourseCode` (normalized).
    static func results(
        matchingSourceCourseCode sourceCourseCode: String,
        in results: [TransferCourseResult]
    ) -> [TransferCourseResult] {
        let target = CatalogImportTransforms.normalizeCourseCode(sourceCourseCode)
        guard !target.isEmpty else { return [] }
        return results.filter {
            CatalogImportTransforms.normalizeCourseCode($0.sourceCourseCode) == target
        }
    }

    /// Returns results whose target course matches `targetCourseCode` (normalized).
    static func results(
        matchingTargetCourseCode targetCourseCode: String,
        in results: [TransferCourseResult]
    ) -> [TransferCourseResult] {
        let target = CatalogImportTransforms.normalizeCourseCode(targetCourseCode)
        guard !target.isEmpty else { return [] }
        return results.filter {
            CatalogImportTransforms.normalizeCourseCode($0.targetCourseCode) == target
        }
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
}
