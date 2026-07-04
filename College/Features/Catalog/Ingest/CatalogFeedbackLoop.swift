// CatalogFeedbackLoop.swift
// Feature: Catalog
// Purpose: Production misses become locked regression fixtures (P18).

import Foundation

struct CatalogRegressionFixture: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    let schoolID: String
    let entityKind: String
    let expectedKey: String
    let actualKey: String?
    let sourceURL: String?
    let createdAt: Date
    let locked: Bool
}

enum CatalogFeedbackLoop {
    private static let key = "catalog.feedback.regression.v1"

    static func recordMiss(
        schoolID: String,
        entityKind: String,
        expectedKey: String,
        actualKey: String?,
        sourceURL: String? = nil
    ) {
        var fixtures = loadAll()
        let fixture = CatalogRegressionFixture(
            id: UUID(),
            schoolID: schoolID,
            entityKind: entityKind,
            expectedKey: expectedKey,
            actualKey: actualKey,
            sourceURL: sourceURL,
            createdAt: .now,
            locked: true
        )
        fixtures.append(fixture)
        if fixtures.count > 500 {
            fixtures = Array(fixtures.suffix(500))
        }
        if let data = try? JSONEncoder().encode(fixtures) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func loadAll() -> [CatalogRegressionFixture] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([CatalogRegressionFixture].self, from: data) else {
            return []
        }
        return decoded
    }

    static func lockedFixtures(for schoolID: String) -> [CatalogRegressionFixture] {
        loadAll().filter { $0.schoolID == schoolID && $0.locked }
    }
}
