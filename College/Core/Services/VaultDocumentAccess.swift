// VaultDocumentAccess.swift
// Feature: Core
// Purpose: Core module — VaultDocumentAccess.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftData

/// local store-backed vault file access (Phase 7f UI cutover).
@MainActor
enum VaultDocumentAccess {
    static func document(id: UUID, collegePersistence: CollegePersistence = .shared) -> VaultDocument? {
        try? collegePersistence.vaultRepository.fetchDocument(id: id)
    }

    static func urlForDocument(id: UUID, collegePersistence: CollegePersistence = .shared) -> URL? {
        guard let doc = document(id: id, collegePersistence: collegePersistence),
              !doc.localRelativePath.isEmpty else { return nil }
        return collegePersistence.urlForVaultRelativePath(doc.localRelativePath)
    }

    static func decryptedTempURL(for id: UUID, collegePersistence: CollegePersistence = .shared) async -> URL? {
        guard let doc = document(id: id, collegePersistence: collegePersistence),
              !doc.localRelativePath.isEmpty else { return nil }
        return collegePersistence.decryptedTempURLForStoredRelativePath(
            doc.localRelativePath,
            displayFileName: doc.fileName
        )
    }

    static func markOpened(id: UUID, collegePersistence: CollegePersistence = .shared) {
        guard let doc = document(id: id, collegePersistence: collegePersistence) else { return }
        collegePersistence.markVaultDocumentOpened(doc)
    }

    static func delete(id: UUID, collegePersistence: CollegePersistence = .shared) {
        collegePersistence.deleteVaultDocument(id: id)
    }

    static func rename(id: UUID, newName: String, collegePersistence: CollegePersistence = .shared) {
        guard let doc = document(id: id, collegePersistence: collegePersistence) else { return }
        collegePersistence.renameVaultDocument(doc, newName: newName)
    }

    static func toggleFavorite(id: UUID, collegePersistence: CollegePersistence = .shared) {
        guard let doc = document(id: id, collegePersistence: collegePersistence) else { return }
        collegePersistence.toggleVaultDocumentFavorite(doc)
    }

    static func moveToFolder(id: UUID, folderID: UUID?, collegePersistence: CollegePersistence = .shared) {
        guard let doc = document(id: id, collegePersistence: collegePersistence) else { return }
        collegePersistence.moveVaultDocument(doc, toFolderID: folderID)
    }
}
