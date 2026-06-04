// CatalogIngestObservability.swift
// Feature: Catalog
// Purpose: Catalog module — CatalogIngestMetricSample.
// Data: CollegePersistence / repositories when applicable.

import Foundation

struct CatalogIngestMetricSample: Codable, Sendable {
    let schoolID: String
    let source: String
    let succeeded: Bool
    let durationMs: Int
    let pageCount: Int
    let ocrPagesUsed: Int
    let averageProgramConfidence: Double?
    let timestamp: Date
}

enum CatalogIngestObservability {
    private static let key = "catalog.ingest.observability.v1"

    static func record(_ sample: CatalogIngestMetricSample) {
        var all = loadAll()
        all.append(sample)
        // Keep bounded history for diagnostics UI.
        if all.count > 200 {
            all = Array(all.suffix(200))
        }
        if let data = try? JSONEncoder().encode(all) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func loadAll() -> [CatalogIngestMetricSample] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([CatalogIngestMetricSample].self, from: data) else {
            return []
        }
        return decoded
    }

    static func summarizeRecent(limit: Int = 30) -> (failureRate: Double, avgDurationMs: Double, avgOCRRate: Double) {
        let recent = Array(loadAll().suffix(max(1, limit)))
        guard !recent.isEmpty else { return (0, 0, 0) }
        let failures = recent.filter { !$0.succeeded }.count
        let avgDuration = Double(recent.reduce(0) { $0 + $1.durationMs }) / Double(recent.count)
        let ocrRateParts = recent.map { sample -> Double in
            guard sample.pageCount > 0 else { return 0 }
            return Double(sample.ocrPagesUsed) / Double(sample.pageCount)
        }
        let avgOCRRate = ocrRateParts.reduce(0, +) / Double(ocrRateParts.count)
        return (Double(failures) / Double(recent.count), avgDuration, avgOCRRate)
    }
}
