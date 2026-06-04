// VaultRepository.swift
// Feature: Core/Data
// Purpose: Core/Data persistence — — VaultRepository.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftData

/// Bounded local store fetch helpers for vault documents and watched folders (Phase 7b).
@MainActor
struct VaultRepository {
    let context: ModelContext

    func fetchDocuments(
        category: String? = nil,
        limit: Int = 200,
        offset: Int = 0
    ) throws -> [VaultDocument] {
        let pageLimit = max(1, min(limit, 500))
        let trimmedCategory = category?.trimmingCharacters(in: .whitespacesAndNewlines)

        var descriptor: FetchDescriptor<VaultDocument>
        if let trimmedCategory, !trimmedCategory.isEmpty {
            descriptor = FetchDescriptor<VaultDocument>(
                predicate: #Predicate { doc in
                    doc.isFolder == false && doc.category == trimmedCategory
                },
                sortBy: [
                    SortDescriptor(\.sortOrder, order: .forward),
                    SortDescriptor(\.addedAt, order: .reverse),
                ]
            )
        } else {
            descriptor = FetchDescriptor<VaultDocument>(
                predicate: #Predicate { doc in
                    doc.isFolder == false
                },
                sortBy: [
                    SortDescriptor(\.sortOrder, order: .forward),
                    SortDescriptor(\.addedAt, order: .reverse),
                ]
            )
        }
        descriptor.fetchLimit = pageLimit
        descriptor.fetchOffset = max(0, offset)
        return try context.fetch(descriptor)
    }

    func fetchDocument(id: UUID) throws -> VaultDocument? {
        var descriptor = FetchDescriptor<VaultDocument>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    func fetchWatchedFolders(limit: Int = 40) throws -> [WatchedFolder] {
        var descriptor = FetchDescriptor<WatchedFolder>(
            sortBy: [SortDescriptor(\.addedAt, order: .forward)]
        )
        descriptor.fetchLimit = max(1, limit)
        return try context.fetch(descriptor)
    }

    func fetchDocumentCount(category: String? = nil) throws -> Int {
        if let category, !category.isEmpty {
            return try context.fetchCount(
                FetchDescriptor<VaultDocument>(
                    predicate: #Predicate { $0.isFolder == false && $0.category == category }
                )
            )
        }
        return try context.fetchCount(
            FetchDescriptor<VaultDocument>(
                predicate: #Predicate { $0.isFolder == false }
            )
        )
    }

    /// Files and folders for vault browser UI (Phase 7c).
    func fetchAllVaultItems(limit: Int = 5000) throws -> [VaultDocument] {
        var descriptor = FetchDescriptor<VaultDocument>(
            sortBy: [
                SortDescriptor(\.sortOrder, order: .forward),
                SortDescriptor(\.addedAt, order: .reverse),
            ]
        )
        descriptor.fetchLimit = max(1, min(limit, 5000))
        return try context.fetch(descriptor)
    }
}