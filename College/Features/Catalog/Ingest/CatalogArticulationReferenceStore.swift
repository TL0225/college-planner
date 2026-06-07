// CatalogArticulationReferenceStore.swift
// Feature: Catalog
// Purpose: Optional articulation / Transferology rows keyed by course code per school.
// Data: CollegePersistence / repositories when applicable.

import Foundation

struct CatalogArticulationRow: Codable, Sendable, Equatable {
    let courseCode: String
    let system: String
    let externalID: String
    let url: String?
}

enum CatalogArticulationReferenceStore {
    private static var root: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let url = base.appendingPathComponent("College/CatalogArticulation", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func fileURL(schoolID: String) -> URL {
        let safe = schoolID.replacingOccurrences(of: "/", with: "_")
        return root.appendingPathComponent("\(safe).json")
    }

    static func load(schoolID: String) -> [CatalogArticulationRow] {
        let url = fileURL(schoolID: schoolID)
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([CatalogArticulationRow].self, from: data) else {
            return []
        }
        return decoded
    }

    static func save(_ rows: [CatalogArticulationRow], schoolID: String) {
        let url = fileURL(schoolID: schoolID)
        if let data = try? JSONEncoder().encode(rows) {
            try? data.write(to: url, options: .atomic)
        }
    }

    static func rowsByCourseCode(schoolID: String) -> [String: [CatalogArticulationRow]] {
        var grouped: [String: [CatalogArticulationRow]] = [:]
        for row in load(schoolID: schoolID) {
            let code = CatalogImportTransforms.normalizeCourseCode(row.courseCode)
            guard !code.isEmpty else { continue }
            grouped[code, default: []].append(row)
        }
        return grouped
    }
}
