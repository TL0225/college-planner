// CatalogManifestVerificationRecord.swift
// Feature: Catalog
// Purpose: Persist live probe evidence for manifest declared vs detected format.

import Foundation

struct CatalogManifestVerificationRecord: Codable, Sendable, Equatable {
    let schoolID: String
    let declaredFormat: String
    let detectedFormat: String
    let confidence: Double
    let margin: Double
    let evidence: [String]
    let finalURL: String
    let probedAt: Date
    let blockedByWAF: Bool
    let notACatalogHost: Bool

    var mismatch: Bool {
        let declared = declaredFormat.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let detected = detectedFormat.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !declared.isEmpty, !detected.isEmpty, detected != "unknown" else { return false }
        let declaredPlatform = CatalogDetectedPlatform.from(manifestFormat: declared)
        let detectedPlatform = CatalogDetectedPlatform.from(manifestFormat: detected)
        return declaredPlatform != detectedPlatform
    }

    var autoOverrideEligible: Bool {
        CatalogPlatformFingerprintStore.shouldAutoOverride(
            declared: CatalogDetectedPlatform.from(manifestFormat: declaredFormat),
            detected: CatalogDetectedPlatform.from(manifestFormat: detectedFormat),
            confidence: confidence,
            margin: margin
        )
    }
}
