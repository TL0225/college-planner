// CareerApplyAccuracyGate.swift
// Feature: Career / Apply
// Purpose: Profile-first blocking gates before apply window opens.

import Foundation

enum CareerApplyAccuracyGateBlockReason: String, Sendable, Equatable {
    case missingEmail
    case missingProfile
    case missingApplyURL
    case criticalParserHealth
    case missingWorkAuthorization
    case payloadBuildFailed
}

struct CareerApplyAccuracyGateResult: Sendable, Equatable {
    var allowed: Bool
    var reasons: [CareerApplyAccuracyGateBlockReason]
    var warnings: [String]
}

@MainActor
enum CareerApplyAccuracyGate {
    static func evaluate(
        applyURL: URL?,
        resumeDocumentID: UUID?,
        parserHealthPercent: Int?,
        collegePersistence: CollegePersistence = .shared
    ) -> CareerApplyAccuracyGateResult {
        var reasons: [CareerApplyAccuracyGateBlockReason] = []
        var warnings: [String] = []

        if applyURL == nil {
            reasons.append(.missingApplyURL)
        }

        if resumeDocumentID == nil {
            warnings.append("Select a resume before applying.")
        }

        if ProfileReadBridge.primaryProfile(collegePersistence: collegePersistence) == nil {
            reasons.append(.missingProfile)
        } else if let profile = ProfileReadBridge.primaryProfile(collegePersistence: collegePersistence),
                  (profile.universityEmail ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            reasons.append(.missingEmail)
        }

        if let health = parserHealthPercent, health < 50 {
            reasons.append(.criticalParserHealth)
            warnings.append("Resume parser health is critical — review before apply.")
        }

        let repo = CareerRepository(context: collegePersistence.profileContext)
        if let prefs = try? repo.fetchApplicationPreferences() {
            if prefs.usAuthorized == nil && prefs.requiresSponsorshipNow == nil {
                warnings.append("Complete Apply Profile work authorization for screening autofill.")
            }
        } else {
            warnings.append("Set work authorization in Apply Profile.")
        }

        return CareerApplyAccuracyGateResult(
            allowed: reasons.isEmpty,
            reasons: reasons,
            warnings: warnings
        )
    }
}
