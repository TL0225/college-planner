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
    let programsFound: Int?
    let coursesFound: Int?
    let requirementsFound: Int?
    let layoutProfileID: String?
    let discoveryTelemetry: [String: Int]?
    let retryCount: Int?
    let layoutProfileCounts: [String: Int]?
    let wafFallbackUsed: Bool?
    let signatureVersion: String?

    init(
        schoolID: String,
        source: String,
        succeeded: Bool,
        durationMs: Int,
        pageCount: Int,
        ocrPagesUsed: Int,
        averageProgramConfidence: Double?,
        timestamp: Date,
        programsFound: Int? = nil,
        coursesFound: Int? = nil,
        requirementsFound: Int? = nil,
        layoutProfileID: String? = nil,
        discoveryTelemetry: [String: Int]? = nil,
        retryCount: Int? = nil,
        layoutProfileCounts: [String: Int]? = nil,
        wafFallbackUsed: Bool? = nil,
        signatureVersion: String? = nil
    ) {
        self.schoolID = schoolID
        self.source = source
        self.succeeded = succeeded
        self.durationMs = durationMs
        self.pageCount = pageCount
        self.ocrPagesUsed = ocrPagesUsed
        self.averageProgramConfidence = averageProgramConfidence
        self.timestamp = timestamp
        self.programsFound = programsFound
        self.coursesFound = coursesFound
        self.requirementsFound = requirementsFound
        self.layoutProfileID = layoutProfileID
        self.discoveryTelemetry = discoveryTelemetry
        self.retryCount = retryCount
        self.layoutProfileCounts = layoutProfileCounts
        self.wafFallbackUsed = wafFallbackUsed
        self.signatureVersion = signatureVersion
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schoolID = try container.decode(String.self, forKey: .schoolID)
        source = try container.decode(String.self, forKey: .source)
        succeeded = try container.decode(Bool.self, forKey: .succeeded)
        durationMs = try container.decode(Int.self, forKey: .durationMs)
        pageCount = try container.decode(Int.self, forKey: .pageCount)
        ocrPagesUsed = try container.decode(Int.self, forKey: .ocrPagesUsed)
        averageProgramConfidence = try container.decodeIfPresent(Double.self, forKey: .averageProgramConfidence)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        programsFound = try container.decodeIfPresent(Int.self, forKey: .programsFound)
        coursesFound = try container.decodeIfPresent(Int.self, forKey: .coursesFound)
        requirementsFound = try container.decodeIfPresent(Int.self, forKey: .requirementsFound)
        layoutProfileID = try container.decodeIfPresent(String.self, forKey: .layoutProfileID)
        discoveryTelemetry = try container.decodeIfPresent([String: Int].self, forKey: .discoveryTelemetry)
        retryCount = try container.decodeIfPresent(Int.self, forKey: .retryCount)
        layoutProfileCounts = try container.decodeIfPresent([String: Int].self, forKey: .layoutProfileCounts)
        wafFallbackUsed = try container.decodeIfPresent(Bool.self, forKey: .wafFallbackUsed)
        signatureVersion = try container.decodeIfPresent(String.self, forKey: .signatureVersion)
    }
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

    static func summarizeRecent(limit: Int = 30) -> (
        failureRate: Double,
        avgDurationMs: Double,
        avgOCRRate: Double,
        discoveryTelemetryCounts: [String: Int]
    ) {
        let recent = Array(loadAll().suffix(max(1, limit)))
        guard !recent.isEmpty else { return (0, 0, 0, [:]) }
        let failures = recent.filter { !$0.succeeded }.count
        let avgDuration = Double(recent.reduce(0) { $0 + $1.durationMs }) / Double(recent.count)
        let ocrRateParts = recent.map { sample -> Double in
            guard sample.pageCount > 0 else { return 0 }
            return Double(sample.ocrPagesUsed) / Double(sample.pageCount)
        }
        let avgOCRRate = ocrRateParts.reduce(0, +) / Double(ocrRateParts.count)
        var discoveryCounts: [String: Int] = [:]
        for sample in recent {
            guard let telemetry = sample.discoveryTelemetry else { continue }
            for (key, value) in telemetry {
                discoveryCounts[key, default: 0] += value
            }
        }
        return (Double(failures) / Double(recent.count), avgDuration, avgOCRRate, discoveryCounts)
    }
}
