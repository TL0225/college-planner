// CatalogReviewSnapshot.swift
// Feature: Catalog
// Purpose: Review queue context snapshots (URL, excerpt, metrics) for operator triage.
// Data: CollegePersistence / repositories when applicable.

import Foundation

struct CatalogReviewSnapshot: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    let schoolID: String
    let reason: String
    let severity: CatalogReviewSeverity
    let sourceURL: String?
    let excerpt: String?
    let layoutProfileID: String?
    let metrics: CatalogExtractorMetrics?
    let createdAt: Date

    init(
        id: UUID = UUID(),
        schoolID: String,
        reason: String,
        severity: CatalogReviewSeverity,
        sourceURL: String? = nil,
        excerpt: String? = nil,
        layoutProfileID: String? = nil,
        metrics: CatalogExtractorMetrics? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.schoolID = schoolID
        self.reason = reason
        self.severity = severity
        self.sourceURL = sourceURL
        self.excerpt = excerpt
        self.layoutProfileID = layoutProfileID
        self.metrics = metrics
        self.createdAt = createdAt
    }

    static func from(
        schoolID: String,
        reason: String,
        severity: CatalogReviewSeverity,
        metrics: CatalogExtractorMetrics?,
        messages: [String] = []
    ) -> CatalogReviewSnapshot {
        CatalogReviewSnapshot(
            schoolID: schoolID,
            reason: reason,
            severity: severity,
            excerpt: messages.isEmpty ? nil : messages.joined(separator: " · "),
            layoutProfileID: metrics?.layoutProfileID,
            metrics: metrics
        )
    }
}

enum CatalogReviewSnapshotStore {
    private static var root: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let url = base.appendingPathComponent("College/CatalogReviewSnapshots", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func save(_ snapshot: CatalogReviewSnapshot) {
        let url = root.appendingPathComponent("\(snapshot.id.uuidString).json")
        if let data = try? JSONEncoder().encode(snapshot) {
            try? data.write(to: url, options: .atomic)
        }
    }

    static func load(id: UUID) -> CatalogReviewSnapshot? {
        let url = root.appendingPathComponent("\(id.uuidString).json")
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(CatalogReviewSnapshot.self, from: data) else {
            return nil
        }
        return decoded
    }
}
