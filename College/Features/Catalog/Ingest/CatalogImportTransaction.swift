// CatalogImportTransaction.swift
// Feature: Catalog
// Purpose: Snapshot -> validate -> publish -> rollback transactional imports (P25).

import Foundation

enum CatalogImportTransactionPhase: String, Codable, Sendable {
    case snapshot
    case validated
    case published
    case rolledBack
}

struct CatalogImportSnapshot: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    let schoolID: String
    let catalogVersionID: String
    let phase: CatalogImportTransactionPhase
    let evaluationScore: Double?
    let createdAt: Date
    let programCount: Int
    let courseCount: Int
    let requirementCount: Int
}

enum CatalogImportTransaction {
    private static let key = "catalog.import.transactions.v1"

    static func beginSnapshot(
        schoolID: String,
        catalogVersionID: String,
        programCount: Int,
        courseCount: Int,
        requirementCount: Int
    ) -> CatalogImportSnapshot {
        CatalogImportSnapshot(
            id: UUID(),
            schoolID: schoolID,
            catalogVersionID: catalogVersionID,
            phase: .snapshot,
            evaluationScore: nil,
            createdAt: .now,
            programCount: programCount,
            courseCount: courseCount,
            requirementCount: requirementCount
        )
    }

    static func shouldPublish(evaluation: CatalogEvaluationReport, minimumScore: Double = 0.5) -> Bool {
        evaluation.overallQualityScore >= minimumScore
    }

    static func advance(
        _ snapshot: CatalogImportSnapshot,
        to phase: CatalogImportTransactionPhase,
        evaluationScore: Double? = nil
    ) -> CatalogImportSnapshot {
        CatalogImportSnapshot(
            id: snapshot.id,
            schoolID: snapshot.schoolID,
            catalogVersionID: snapshot.catalogVersionID,
            phase: phase,
            evaluationScore: evaluationScore ?? snapshot.evaluationScore,
            createdAt: snapshot.createdAt,
            programCount: snapshot.programCount,
            courseCount: snapshot.courseCount,
            requirementCount: snapshot.requirementCount
        )
    }

    static func persist(_ snapshot: CatalogImportSnapshot) {
        var all = loadAll()
        all.append(snapshot)
        if all.count > 100 { all = Array(all.suffix(100)) }
        if let data = try? JSONEncoder().encode(all) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func loadAll() -> [CatalogImportSnapshot] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([CatalogImportSnapshot].self, from: data) else {
            return []
        }
        return decoded
    }

    static func latest(for schoolID: String) -> CatalogImportSnapshot? {
        loadAll().filter { $0.schoolID == schoolID }.max(by: { $0.createdAt < $1.createdAt })
    }
}
