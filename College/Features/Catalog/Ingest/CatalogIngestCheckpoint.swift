// CatalogIngestCheckpoint.swift
// Feature: Catalog
// Purpose: Catalog module — CatalogIntegrityReport.
// Data: CollegePersistence / repositories when applicable.

import Foundation

/// Lightweight ingest checkpoint + cancel flags (UserDefaults-backed).
enum CatalogIngestCheckpoint {
    private static let prefix = "catalog.ingest.checkpoint.v1."
    private static let cancelPrefix = "catalog.ingest.cancel.v1."

    enum Stage: String, Sendable {
        case passA
        case passB
        case archive
        case vectors
    }

    static func save(stage: Stage, schoolID: String, signature: String?) {
        var payload: [String: String] = [
            "stage": stage.rawValue,
            "updatedAt": ISO8601DateFormatter().string(from: Date()),
        ]
        if let signature, !signature.isEmpty {
            payload["signature"] = signature
        }
        UserDefaults.standard.set(payload, forKey: prefix + schoolID)
    }

    static func load(schoolID: String) -> [String: String]? {
        UserDefaults.standard.dictionary(forKey: prefix + schoolID) as? [String: String]
    }

    static func requestCancel(schoolID: String) {
        UserDefaults.standard.set(true, forKey: cancelPrefix + schoolID)
    }

    static func clearCancel(schoolID: String) {
        UserDefaults.standard.removeObject(forKey: cancelPrefix + schoolID)
    }

    static func isCancelRequested(schoolID: String) -> Bool {
        UserDefaults.standard.bool(forKey: cancelPrefix + schoolID)
    }

    static func throwIfCancelled(schoolID: String) throws {
        if isCancelRequested(schoolID: schoolID) {
            throw CatalogIngestCancellation.schoolCancelled(schoolID)
        }
    }
}

enum CatalogIngestCancellation: Error, LocalizedError {
    case schoolCancelled(String)

    var errorDescription: String? {
        switch self {
        case .schoolCancelled(let id):
            return "Catalog import for \(id) was cancelled."
        }
    }
}

/// Post-ingest integrity snapshot for Settings diagnostics.
struct CatalogIntegrityReport: Codable, Sendable {
    let schoolID: String
    let schoolName: String
    let generatedAt: Date
    let coursesInStore: Int
    let programsInStore: Int
    let requirementsInStore: Int
    let academicReady: Bool
    let archiveReady: Bool
    let vectorsReady: Bool
    let warnings: [String]

    private static let storagePrefix = "catalog.integrity.report.v1."

    static func save(_ report: CatalogIntegrityReport) {
        guard let data = try? JSONEncoder().encode(report) else { return }
        UserDefaults.standard.set(data, forKey: storagePrefix + report.schoolID)
    }

    static func load(schoolID: String) -> CatalogIntegrityReport? {
        guard let data = UserDefaults.standard.data(forKey: storagePrefix + schoolID) else { return nil }
        return try? JSONDecoder().decode(CatalogIntegrityReport.self, from: data)
    }
}
