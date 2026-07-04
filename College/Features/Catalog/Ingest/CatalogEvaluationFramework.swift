// CatalogEvaluationFramework.swift
// Feature: Catalog
// Purpose: Aggregate measurement signals into an Overall Quality Score (P22).

import Foundation

struct CatalogEvaluationReport: Codable, Sendable, Equatable {
    let schoolID: String
    let catalogVersionID: String
    let overallQualityScore: Double
    let programPrecision: Double?
    let programRecall: Double?
    let requirementPrecision: Double?
    let requirementRecall: Double?
    let coverageScore: Double?
    let fallbackRate: Double?
    let rawPreservationRate: Double?
    let calibrationScore: Double?
    let recordedAt: Date

    var summaryLine: String {
        String(format: "OQS %.1f%% (P %.2f R %.2f)", overallQualityScore * 100, programPrecision ?? 0, programRecall ?? 0)
    }
}

enum CatalogEvaluationFramework {
    static func score(
        schoolID: String,
        catalogVersionID: String,
        programsFound: Int,
        coursesFound: Int,
        requirementsFound: Int,
        benchmarkPrecision: Double?,
        benchmarkRecall: Double?,
        requirementPrecision: Double?,
        requirementRecall: Double?,
        fallbackRate: Double = 0,
        rawPreserved: Bool = false,
        calibrationScore: Double? = nil
    ) -> CatalogEvaluationReport {
        let coverageParts: [Double] = [
            programsFound > 0 ? 1 : 0,
            coursesFound > 0 ? 1 : 0,
            requirementsFound > 0 ? 1 : 0,
        ]
        let coverage = coverageParts.reduce(0, +) / Double(coverageParts.count)

        let precision = benchmarkPrecision ?? requirementPrecision ?? 0.5
        let recall = benchmarkRecall ?? requirementRecall ?? 0.5
        let f1 = (precision + recall) > 0 ? (2 * precision * recall) / (precision + recall) : 0
        let fallbackPenalty = min(0.25, fallbackRate * 0.25)
        let rawBonus = rawPreserved ? 0.05 : 0
        let calibration = calibrationScore ?? 0.5

        let oqs = min(1, max(0,
            0.35 * f1 +
            0.25 * coverage +
            0.20 * calibration +
            0.15 * (1 - fallbackPenalty) +
            rawBonus
        ))

        return CatalogEvaluationReport(
            schoolID: schoolID,
            catalogVersionID: catalogVersionID,
            overallQualityScore: oqs,
            programPrecision: benchmarkPrecision,
            programRecall: benchmarkRecall,
            requirementPrecision: requirementPrecision,
            requirementRecall: requirementRecall,
            coverageScore: coverage,
            fallbackRate: fallbackRate,
            rawPreservationRate: rawPreserved ? 1 : 0,
            calibrationScore: calibration,
            recordedAt: .now
        )
    }
}
