// CatalogEditionStore.swift
// Feature: Catalog
// Purpose: Persist and resolve CatalogEdition records (P9).

import Foundation
import SwiftData

@MainActor
enum CatalogEditionStore {
    static func upsertEdition(
        context: ModelContext,
        university: University,
        editionKey: String,
        schoolID: String,
        label: String,
        sourceHash: String?,
        parserVersion: String?,
        replayConfigJSON: String?,
        publish: Bool = false
    ) throws -> CatalogEdition {
        let trimmedKey = editionKey.trimmingCharacters(in: .whitespacesAndNewlines)
        var descriptor = FetchDescriptor<CatalogEdition>(
            predicate: #Predicate { $0.editionKey == trimmedKey }
        )
        descriptor.fetchLimit = 1
        let edition: CatalogEdition
        if let existing = try context.fetch(descriptor).first {
            edition = existing
        } else {
            edition = CatalogEdition(editionKey: trimmedKey, schoolID: schoolID, label: label)
            edition.university = university
            context.insert(edition)
        }
        edition.label = label
        edition.schoolID = schoolID
        edition.sourceHash = sourceHash
        edition.parserVersion = parserVersion
        edition.replayConfigJSON = replayConfigJSON
        if publish {
            edition.isPublished = true
        }
        return edition
    }

    static func publishedEditionKey(
        context: ModelContext,
        schoolID: String
    ) throws -> String? {
        let trimmed = schoolID.trimmingCharacters(in: .whitespacesAndNewlines)
        var descriptor = FetchDescriptor<CatalogEdition>(
            predicate: #Predicate { $0.schoolID == trimmed && $0.isPublished == true }
        )
        descriptor.sortBy = [SortDescriptor(\.createdAt, order: .reverse)]
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first?.editionKey
    }
}
