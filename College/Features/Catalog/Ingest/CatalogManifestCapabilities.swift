// CatalogManifestCapabilities.swift
// Feature: Catalog
// Purpose: Per-school capability metadata (transfer, articulation) beyond engine defaults.
// Data: CollegePersistence / repositories when applicable.

import Foundation

struct CatalogManifestCapabilities: Codable, Sendable, Equatable {
    let supportsTransferEquivalencies: Bool
    let supportsArticulationIngest: Bool

    static let `default` = CatalogManifestCapabilities(
        supportsTransferEquivalencies: false,
        supportsArticulationIngest: false
    )
}

enum CatalogManifestCapabilityStore {
    private static let keyPrefix = "catalog.manifest.capabilities.v1."

    static func capabilities(forSchoolID schoolID: String, format: String?) -> CatalogManifestCapabilities {
        let trimmed = schoolID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let data = UserDefaults.standard.data(forKey: keyPrefix + trimmed),
              let decoded = try? JSONDecoder().decode(CatalogManifestCapabilities.self, from: data) else {
            return inferredDefaults(format: format)
        }
        return decoded
    }

    static func save(_ capabilities: CatalogManifestCapabilities, schoolID: String) {
        let trimmed = schoolID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let data = try? JSONEncoder().encode(capabilities) else { return }
        UserDefaults.standard.set(data, forKey: keyPrefix + trimmed)
    }

    private static func inferredDefaults(format: String?) -> CatalogManifestCapabilities {
        let engine = CatalogIngestEngine(manifestFormat: format)
        let base = CatalogEngineCapabilityDefaults.shared.capabilities(for: engine)
        return CatalogManifestCapabilities(
            supportsTransferEquivalencies: base.supportsTransferEquivalencies,
            supportsArticulationIngest: base.supportsArticulationIngest
        )
    }
}
