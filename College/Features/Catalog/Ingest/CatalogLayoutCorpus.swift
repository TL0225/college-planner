// CatalogLayoutCorpus.swift
// Feature: Catalog
// Purpose: Organic layout corpus — grow from successful ingests (Tier 3, low cost).
// Data: CollegePersistence / repositories when applicable.

import Foundation

struct CatalogLayoutCorpusEntry: Codable, Sendable, Equatable, Identifiable {
    var id: String { "\(schoolID)::\(layoutProfileID)::\(engine)" }
    let schoolID: String
    let engine: String
    let layoutProfileID: String
    let featureSignature: String
    let exampleURLs: [String]
    let quirks: [String]
    let recordedAt: Date

    static func from(
        metrics: CatalogExtractorMetrics,
        fingerprint: CatalogLayoutFingerprint,
        exampleURL: String? = nil
    ) -> CatalogLayoutCorpusEntry {
        var urls: [String] = []
        if let exampleURL {
            let trimmed = exampleURL.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { urls.append(trimmed) }
        }
        return CatalogLayoutCorpusEntry(
            schoolID: metrics.schoolID,
            engine: metrics.source,
            layoutProfileID: fingerprint.layoutProfileID,
            featureSignature: fingerprint.featureSignature,
            exampleURLs: urls,
            quirks: [],
            recordedAt: Date()
        )
    }
}

enum CatalogLayoutCorpus {
    private static var root: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let url = base.appendingPathComponent("College/CatalogLayoutCorpus", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func record(
        metrics: CatalogExtractorMetrics,
        fingerprint: CatalogLayoutFingerprint,
        exampleURL: String? = nil
    ) {
        let entry = CatalogLayoutCorpusEntry.from(
            metrics: metrics,
            fingerprint: fingerprint,
            exampleURL: exampleURL
        )
        let safeSchool = entry.schoolID.replacingOccurrences(of: "/", with: "_")
        let safeProfile = entry.layoutProfileID.replacingOccurrences(of: "/", with: "_")
        let url = root.appendingPathComponent("\(safeSchool)__\(safeProfile).json")
        if let data = try? JSONEncoder().encode(entry) {
            try? data.write(to: url, options: .atomic)
        }
    }

    static func load(schoolID: String, layoutProfileID: String) -> CatalogLayoutCorpusEntry? {
        let safeSchool = schoolID.replacingOccurrences(of: "/", with: "_")
        let safeProfile = layoutProfileID.replacingOccurrences(of: "/", with: "_")
        let url = root.appendingPathComponent("\(safeSchool)__\(safeProfile).json")
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(CatalogLayoutCorpusEntry.self, from: data) else {
            return nil
        }
        return decoded
    }
}
