// CatalogEntityIdentityStore.swift
// Feature: Catalog
// Purpose: Application Support JSON cache of catalog entity identities per school + version.
// Data: CollegePersistence / repositories when applicable.

import Foundation

enum CatalogEntityIdentityStore {
    private static var root: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let url = base.appendingPathComponent("College/CatalogIdentities", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func fileURL(schoolID: String, catalogVersionID: String) -> URL {
        let safeSchool = schoolID.replacingOccurrences(of: "/", with: "_")
        let safeVersion = catalogVersionID.replacingOccurrences(of: "/", with: "_")
        return root.appendingPathComponent("\(safeSchool)__\(safeVersion).json")
    }

    static func load(schoolID: String, catalogVersionID: String) -> [CatalogEntityIdentity] {
        let url = fileURL(schoolID: schoolID, catalogVersionID: catalogVersionID)
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([CatalogEntityIdentity].self, from: data) else {
            return []
        }
        return decoded
    }

    static func save(_ identities: [CatalogEntityIdentity], schoolID: String, catalogVersionID: String) {
        let url = fileURL(schoolID: schoolID, catalogVersionID: catalogVersionID)
        if let data = try? JSONEncoder().encode(identities) {
            try? data.write(to: url, options: .atomic)
        }
    }

    static func merge(
        persisted: [CatalogEntityIdentity],
        stored: [CatalogEntityIdentity]
    ) -> [CatalogEntityIdentity] {
        var byKey: [String: CatalogEntityIdentity] = [:]
        for identity in stored {
            byKey[identityKey(identity)] = identity
        }
        for identity in persisted {
            byKey[identityKey(identity)] = identity
        }
        return Array(byKey.values)
    }

    private static func identityKey(_ identity: CatalogEntityIdentity) -> String {
        "\(identity.entityType.rawValue)|\(identity.catalogVersionID)|\(identity.displayKey)"
    }
}
