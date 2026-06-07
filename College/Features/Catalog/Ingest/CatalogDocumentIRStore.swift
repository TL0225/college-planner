// CatalogDocumentIRStore.swift
// Feature: Catalog
// Purpose: Application Support JSON cache of CatalogDocumentIR per school + catalog version.
// Data: CollegePersistence / repositories when applicable.

import Foundation

enum CatalogDocumentIRStore {
    private static var root: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let url = base.appendingPathComponent("College/CatalogDocumentIR", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func fileURL(schoolID: String, catalogVersionID: String) -> URL {
        let safeSchool = schoolID.replacingOccurrences(of: "/", with: "_")
        let safeVersion = catalogVersionID.replacingOccurrences(of: "/", with: "_")
        return root.appendingPathComponent("\(safeSchool)__\(safeVersion).json")
    }

    static func load(schoolID: String, catalogVersionID: String) -> CatalogDocumentIR? {
        let url = fileURL(schoolID: schoolID, catalogVersionID: catalogVersionID)
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(CatalogDocumentIR.self, from: data) else {
            return nil
        }
        return decoded
    }

    static func save(_ ir: CatalogDocumentIR, schoolID: String, catalogVersionID: String) {
        let url = fileURL(schoolID: schoolID, catalogVersionID: catalogVersionID)
        if let data = try? JSONEncoder().encode(ir) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
