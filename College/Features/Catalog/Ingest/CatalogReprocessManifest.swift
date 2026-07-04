// CatalogReprocessManifest.swift
// Feature: Catalog
// Purpose: Deterministic replay tuple for catalog reprocessing (P30).

import Foundation

struct CatalogReprocessManifest: Codable, Sendable, Equatable {
    let schoolID: String
    let catalogVersionID: String
    let sourceHash: String
    let parserVersion: String
    let configFlags: [String: Bool]
    let recordedAt: Date

    var replayKey: String {
        "\(schoolID)|\(catalogVersionID)|\(sourceHash)|\(parserVersion)"
    }

    static func capture(
        schoolID: String,
        catalogVersionID: String,
        sourceHash: String,
        parserVersion: String = CatalogParserCapability.version
    ) -> CatalogReprocessManifest {
        CatalogReprocessManifest(
            schoolID: schoolID,
            catalogVersionID: catalogVersionID,
            sourceHash: sourceHash,
            parserVersion: parserVersion,
            configFlags: [
                "documentIR": CatalogPlatformFlags.documentIREnabled,
                "modernCampusIR": CatalogPlatformFlags.modernCampusIREnabled,
                "ingestGate": CatalogPlatformFlags.ingestGateEnabled,
                "layoutLLM": CatalogPlatformFlags.layoutLLMEnabled,
                "entityLLM": CatalogPlatformFlags.entityLLMEnabled,
            ],
            recordedAt: .now
        )
    }

    func matchesCurrentFlags() -> Bool {
        configFlags["documentIR"] == CatalogPlatformFlags.documentIREnabled &&
        configFlags["ingestGate"] == CatalogPlatformFlags.ingestGateEnabled
    }
}

enum CatalogReprocessManifestStore {
    private static let keyPrefix = "catalog.reprocess.manifest.v1."

    static func save(_ manifest: CatalogReprocessManifest) {
        let key = keyPrefix + manifest.replayKey.replacingOccurrences(of: "|", with: "_")
        if let data = try? JSONEncoder().encode(manifest) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func load(schoolID: String, catalogVersionID: String) -> CatalogReprocessManifest? {
        let prefix = keyPrefix
        let keys = UserDefaults.standard.dictionaryRepresentation().keys.filter { $0.hasPrefix(prefix) }
        for key in keys {
            guard let data = UserDefaults.standard.data(forKey: key),
                  let manifest = try? JSONDecoder().decode(CatalogReprocessManifest.self, from: data),
                  manifest.schoolID == schoolID,
                  manifest.catalogVersionID == catalogVersionID else { continue }
            return manifest
        }
        return nil
    }
}
