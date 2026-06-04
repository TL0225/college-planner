// CatalogCanonicalIRStore.swift
// Feature: Catalog
// Purpose: Catalog module — CatalogCanonicalIRStore.
// Data: CollegePersistence / repositories when applicable.

import Foundation

enum CatalogCanonicalIRStore {
    private static var root: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let url = base.appendingPathComponent("College/CatalogIR", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func save(_ ir: CatalogCanonicalIR) {
        let url = root.appendingPathComponent("\(ir.schoolID).json")
        if let data = try? JSONEncoder().encode(ir) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
