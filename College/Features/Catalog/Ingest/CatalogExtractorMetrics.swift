// CatalogExtractorMetrics.swift
// Feature: Catalog
// Purpose: Per-run ingest metrics and historical baselines for sanity checks.
// Data: CollegePersistence / repositories when applicable.

import Foundation

struct CatalogExtractorMetrics: Codable, Sendable, Equatable {
    let schoolID: String
    let catalogVersionID: String
    let source: String
    let layoutProfileID: String?
    let programsFound: Int
    let coursesFound: Int
    let requirementsFound: Int
    let policiesFound: Int
    let requirementTablesFound: Int
    let averageEntityConfidence: Double?
    let averageOwnershipConfidence: Double?
    let recordedAt: Date

    func toObservabilitySample(
        succeeded: Bool,
        durationMs: Int,
        pageCount: Int,
        ocrPagesUsed: Int = 0
    ) -> CatalogIngestMetricSample {
        CatalogIngestMetricSample(
            schoolID: schoolID,
            source: source,
            succeeded: succeeded,
            durationMs: durationMs,
            pageCount: pageCount,
            ocrPagesUsed: ocrPagesUsed,
            averageProgramConfidence: averageEntityConfidence,
            timestamp: recordedAt,
            programsFound: programsFound,
            coursesFound: coursesFound,
            requirementsFound: requirementsFound,
            layoutProfileID: layoutProfileID
        )
    }
}

enum CatalogExtractorMetricsBaselineStore {
    private static let keyPrefix = "catalog.ingest.baseline.v1."

    struct Baseline: Codable, Sendable, Equatable {
        let programsFound: Int
        let coursesFound: Int
        let requirementsFound: Int
        let updatedAt: Date
    }

    static func key(schoolID: String, catalogVersionID: String) -> String {
        "\(keyPrefix)\(schoolID).\(catalogVersionID)"
    }

    static func load(schoolID: String, catalogVersionID: String) -> Baseline? {
        guard let data = UserDefaults.standard.data(forKey: key(schoolID: schoolID, catalogVersionID: catalogVersionID)),
              let decoded = try? JSONDecoder().decode(Baseline.self, from: data) else {
            return nil
        }
        return decoded
    }

    static func save(_ metrics: CatalogExtractorMetrics) {
        let baseline = Baseline(
            programsFound: max(1, metrics.programsFound),
            coursesFound: metrics.coursesFound,
            requirementsFound: metrics.requirementsFound,
            updatedAt: metrics.recordedAt
        )
        if let data = try? JSONEncoder().encode(baseline) {
            UserDefaults.standard.set(data, forKey: key(schoolID: metrics.schoolID, catalogVersionID: metrics.catalogVersionID))
        }
    }

    static func expectedPrograms(schoolID: String, catalogVersionID: String, fallback: Int) -> Int? {
        load(schoolID: schoolID, catalogVersionID: catalogVersionID)?.programsFound ?? (fallback > 0 ? fallback : nil)
    }
}
