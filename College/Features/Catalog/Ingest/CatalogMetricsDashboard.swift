// CatalogMetricsDashboard.swift
// Feature: Catalog
// Purpose: Per-build longitudinal extraction metrics (P12).

import Foundation
import OSLog

struct CatalogMetricsDashboardSnapshot: Codable, Sendable, Equatable {
    let recordedAt: Date
    let sampleCount: Int
    let failureRate: Double
    let averageDurationMs: Double
    let averageOCRRate: Double
    let totalPrograms: Int
    let totalCourses: Int
    let totalRequirements: Int
    let averageConfidence: Double?
    let rawPreservationRate: Double?
    let discoveryTelemetryCounts: [String: Int]
}

enum CatalogMetricsDashboard {
    private static let logger = Logger(subsystem: "Timothy.College", category: "CatalogMetrics")

    static func capture() -> CatalogMetricsDashboardSnapshot {
        let samples = CatalogIngestObservability.loadAll()
        let recent = Array(samples.suffix(50))
        let summary = CatalogIngestObservability.summarizeRecent(limit: 50)
        let totalPrograms = recent.compactMap(\.programsFound).reduce(0, +)
        let totalCourses = recent.compactMap(\.coursesFound).reduce(0, +)
        let totalRequirements = recent.compactMap(\.requirementsFound).reduce(0, +)
        let confidences = recent.compactMap(\.averageProgramConfidence)
        let avgConfidence = confidences.isEmpty ? nil : confidences.reduce(0, +) / Double(confidences.count)

        let snapshot = CatalogMetricsDashboardSnapshot(
            recordedAt: .now,
            sampleCount: recent.count,
            failureRate: summary.failureRate,
            averageDurationMs: summary.avgDurationMs,
            averageOCRRate: summary.avgOCRRate,
            totalPrograms: totalPrograms,
            totalCourses: totalCourses,
            totalRequirements: totalRequirements,
            averageConfidence: avgConfidence,
            rawPreservationRate: nil,
            discoveryTelemetryCounts: summary.discoveryTelemetryCounts
        )
        logger.info("catalog metrics programs=\(totalPrograms) courses=\(totalCourses) reqs=\(totalRequirements) failRate=\(summary.failureRate) telemetryKeys=\(summary.discoveryTelemetryCounts.count)")
        return snapshot
    }
}
