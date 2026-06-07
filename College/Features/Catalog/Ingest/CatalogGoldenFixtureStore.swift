// CatalogGoldenFixtureStore.swift
// Feature: Catalog
// Purpose: Catalog module — Snapshot.
// Data: CollegePersistence / repositories when applicable.

import Foundation

enum CatalogGoldenFixtureStore {
    struct Snapshot: Codable, Sendable {
        let schoolID: String
        let parserVersion: String
        let createdAt: Date
        let programCount: Int
        let courseCount: Int
        let requirementCount: Int
    }

    private static var root: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let url = base.appendingPathComponent("College/CatalogGoldenFixtures", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func save(_ snapshot: Snapshot) {
        let url = root.appendingPathComponent("\(snapshot.schoolID).json")
        if let data = try? JSONEncoder().encode(snapshot) {
            try? data.write(to: url, options: .atomic)
        }
    }
}

enum CatalogReviewQueue {
    struct Item: Codable, Sendable {
        let schoolID: String
        let reason: String
        let confidence: Double?
        let createdAt: Date
        let severity: CatalogReviewSeverity
        let snapshotID: UUID?

        init(
            schoolID: String,
            reason: String,
            confidence: Double? = nil,
            createdAt: Date = Date(),
            severity: CatalogReviewSeverity = .warning,
            snapshotID: UUID? = nil
        ) {
            self.schoolID = schoolID
            self.reason = reason
            self.confidence = confidence
            self.createdAt = createdAt
            self.severity = severity
            self.snapshotID = snapshotID
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            schoolID = try container.decode(String.self, forKey: .schoolID)
            reason = try container.decode(String.self, forKey: .reason)
            confidence = try container.decodeIfPresent(Double.self, forKey: .confidence)
            createdAt = try container.decode(Date.self, forKey: .createdAt)
            severity = try container.decodeIfPresent(CatalogReviewSeverity.self, forKey: .severity) ?? .warning
            snapshotID = try container.decodeIfPresent(UUID.self, forKey: .snapshotID)
        }
    }

    private static let key = "catalog.review.queue.v1"

    static func enqueue(_ item: Item) {
        var items = load()
        items.append(item)
        if items.count > 300 { items = Array(items.suffix(300)) }
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func load() -> [Item] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([Item].self, from: data) else {
            return []
        }
        return decoded
    }
}
