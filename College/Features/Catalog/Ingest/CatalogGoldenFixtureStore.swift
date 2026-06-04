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
