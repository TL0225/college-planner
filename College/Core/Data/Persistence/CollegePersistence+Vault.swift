// CollegePersistence+Vault.swift
// Feature: Core/Data
// Purpose: Core/Data persistence — — CollegePersistence+Vault.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftData

extension CollegePersistence {
    typealias VaultDocumentCategory = VaultRepository.VaultDocumentCategory

    func urlForVaultRelativePath(_ relativePath: String) -> URL? {
        vaultRepository.urlForVaultRelativePath(relativePath)
    }

    func urlForVaultDocument(_ doc: VaultDocument) -> URL? {
        let rel = doc.localRelativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rel.isEmpty else { return nil }
        return urlForVaultRelativePath(rel)
    }

    @MainActor
    func decryptedTempURLForStoredRelativePath(_ relativePath: String, displayFileName: String) -> URL? {
        vaultRepository.decryptedTempURLForStoredRelativePath(relativePath, displayFileName: displayFileName)
    }

    func deleteVaultDocument(id: UUID) {
        if let doc = try? vaultRepository.fetchDocument(id: id),
           !doc.localRelativePath.isEmpty,
           let url = urlForVaultRelativePath(doc.localRelativePath) {
            try? FileManager.default.removeItem(at: url)
        }
        try? vaultRepository.deleteVaultDocument(id: id)
        ModelMergeCoalescer.flushNow()
        fetchVaultDocuments()
        bumpVaultRevision()
    }

    func markVaultDocumentOpened(_ doc: VaultDocument) {
        doc.lastOpenedAt = Date()
        save()
        bumpVaultRevision()
    }

    func renameVaultDocument(_ doc: VaultDocument, newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        doc.customDisplayName = trimmed
        save()
        bumpVaultRevision()
    }

    func toggleVaultDocumentFavorite(_ doc: VaultDocument) {
        doc.isFavorite.toggle()
        save()
        bumpVaultRevision()
    }

    @MainActor
    func addVaultDocument(
        fromSelectedURL url: URL,
        category: VaultDocumentCategory = .other,
        source: String = "vault",
        parentFolderID: UUID? = nil
    ) throws {
        try vaultRepository.addVaultDocument(
            fromSelectedURL: url,
            category: category,
            source: source,
            parentFolderID: parentFolderID
        )
        fetchVaultDocuments()
        bumpVaultRevision()
    }

    @MainActor
    func addVaultDocument(
        fromSelectedURL url: URL,
        category: VaultDocumentCategory = .other,
        source: String = "vault",
        parentFolderID: UUID? = nil
    ) async throws {
        try vaultRepository.addVaultDocument(
            fromSelectedURL: url,
            category: category,
            source: source,
            parentFolderID: parentFolderID
        )
        fetchVaultDocuments()
        bumpVaultRevision()
    }

    @discardableResult
    func createVaultFolderDocument(name: String, parentFolderID: UUID?) -> VaultDocument? {
        (try? vaultRepository.createVaultFolder(name: name, parentFolderID: parentFolderID))
    }

    func moveVaultDocument(_ doc: VaultDocument, toFolderID folderID: UUID?) {
        try? vaultRepository.moveVaultDocument(id: doc.id, toFolderID: folderID)
        fetchVaultDocuments()
        bumpVaultRevision()
    }

    func bulkDeleteVaultDocuments(_ docs: [VaultDocument]) {
        try? vaultRepository.bulkDeleteVaultDocuments(ids: docs.map(\.id))
        fetchVaultDocuments()
        bumpVaultRevision()
    }

    func deleteVaultFolder(_ folder: VaultDocument, includeContents: Bool) {
        try? vaultRepository.deleteVaultFolder(id: folder.id, includeContents: includeContents)
        fetchVaultDocuments()
        bumpVaultRevision()
    }

    func renameVaultFolder(_ folder: VaultDocument, newName: String) {
        try? vaultRepository.renameVaultFolder(id: folder.id, newName: newName)
        fetchVaultDocuments()
        bumpVaultRevision()
    }

    func setVaultDocumentCourseLink(_ doc: VaultDocument, courseCode: String?) {
        try? vaultRepository.setVaultDocumentCourseLink(id: doc.id, courseCode: courseCode)
        fetchVaultDocuments()
        bumpVaultRevision()
    }

    func fetchWatchedFolders() -> [WatchedFolder] {
        (try? vaultRepository.fetchWatchedFolders()) ?? []
    }

    @discardableResult
    func addWatchedFolder(path: String, bookmarkData: Data? = nil) -> WatchedFolder? {
        try? vaultRepository.addWatchedFolder(path: path, bookmarkData: bookmarkData)
    }

    func removeWatchedFolder(id: UUID) {
        try? vaultRepository.removeWatchedFolder(id: id)
    }

    func updateWatchedFolderBookmark(id: UUID, bookmarkData: Data) {
        try? vaultRepository.updateWatchedFolderBookmark(id: id, bookmarkData: bookmarkData)
    }

    func updateVaultDocumentSummary(id: UUID, summary: String) {
        VaultDocumentMetadataAccess.updateSummary(id: id, summary: summary)
    }

    func linkVaultDocument(id: UUID, toTask taskID: UUID) {
        VaultDocumentMetadataAccess.linkToTask(id: id, taskID: taskID)
    }

    func updateReadingProgress(id: UUID, page: Int, totalPages: Int) {
        VaultDocumentMetadataAccess.updateReadingProgress(id: id, page: page, totalPages: totalPages)
    }

    func markVaultDocumentNeedsReview(id: UUID, courseCode: String?, confidence: Float) {
        VaultDocumentMetadataAccess.markNeedsReview(id: id, courseCode: courseCode, confidence: confidence)
    }

    func confirmVaultDocumentReview(id: UUID, courseCode: String?, category: VaultDocumentCategory) {
        VaultDocumentMetadataAccess.confirmReview(id: id, courseCode: courseCode, category: category.rawValue)
    }

    func markVaultDuplicate(id: UUID, versionOf primaryID: UUID) {
        VaultDocumentMetadataAccess.markDuplicate(id: id, versionOf: primaryID)
    }
}