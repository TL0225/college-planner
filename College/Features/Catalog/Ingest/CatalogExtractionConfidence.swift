// CatalogExtractionConfidence.swift
// Feature: Catalog
// Purpose: Catalog module — CatalogExtractionConfidence.
// Data: CollegePersistence / repositories when applicable.

import Foundation

enum CatalogExtractionConfidenceLevel: String, Codable, Sendable, CaseIterable {
    case high
    case medium
    case low
}

/// Shared confidence payload for engine adapters.
struct CatalogExtractionConfidence: Codable, Sendable, Equatable {
    let score: Double
    let level: CatalogExtractionConfidenceLevel
    let reasons: [String]

    init(score: Double, reasons: [String] = []) {
        let clamped = min(max(score, 0), 1)
        self.score = clamped
        self.level = CatalogExtractionConfidence.level(for: clamped)
        self.reasons = reasons
    }

    private static func level(for score: Double) -> CatalogExtractionConfidenceLevel {
        switch score {
        case 0.8...:
            return .high
        case 0.5..<0.8:
            return .medium
        default:
            return .low
        }
    }
}

/// Shared policy used by reconciliation safety gates.
struct CatalogConfidencePolicy: Codable, Sendable, Equatable {
    let warningThreshold: Double
    let holdThreshold: Double

    static let `default` = CatalogConfidencePolicy(
        warningThreshold: 0.65,
        holdThreshold: 0.35
    )

    func shouldWarn(for confidence: CatalogExtractionConfidence) -> Bool {
        confidence.score < warningThreshold
    }

    func shouldHoldDestructiveWrites(for confidence: CatalogExtractionConfidence) -> Bool {
        confidence.score < holdThreshold
    }
}
