// CatalogEntityLLMValidationStore.swift
// Feature: Catalog
// Purpose: Persist async entity LLM validation results keyed by review snapshot ID.
// Data: CollegePersistence / repositories when applicable.

import Foundation

struct CatalogEntityLLMValidationRecord: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    let snapshotID: UUID
    let schoolID: String
    let validatedAt: Date
    let result: CatalogEntityLLMValidator.ValidationResult

    init(
        id: UUID = UUID(),
        snapshotID: UUID,
        schoolID: String,
        validatedAt: Date = Date(),
        result: CatalogEntityLLMValidator.ValidationResult
    ) {
        self.id = id
        self.snapshotID = snapshotID
        self.schoolID = schoolID
        self.validatedAt = validatedAt
        self.result = result
    }
}

enum CatalogEntityLLMValidationStore {
    private static var root: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let url = base.appendingPathComponent("College/CatalogEntityLLMValidations", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func fileURL(snapshotID: UUID) -> URL {
        root.appendingPathComponent("\(snapshotID.uuidString).json")
    }

    static func save(_ record: CatalogEntityLLMValidationRecord) {
        let url = fileURL(snapshotID: record.snapshotID)
        if let data = try? JSONEncoder().encode(record) {
            try? data.write(to: url, options: .atomic)
        }
    }

    static func load(snapshotID: UUID) -> CatalogEntityLLMValidationRecord? {
        let url = fileURL(snapshotID: snapshotID)
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(CatalogEntityLLMValidationRecord.self, from: data) else {
            return nil
        }
        return decoded
    }
}
