// VaultRepository+Writes.swift
// Feature: Core/Data
// Purpose: Core/Data persistence — — VaultRepository+Writes.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftData

// MARK: - Phase 7f vault writes (local store-native)

extension VaultRepository {
    /// Keeps `parentFolderID` and `@Relationship parentFolder` aligned (DM-R1).
    func syncParentFolderRelationship(for document: VaultDocument) {
        guard let parentID = document.parentFolderID else {
            document.parentFolder = nil
            return
        }
        document.parentFolder = try? fetchDocument(id: parentID)
    }

    /// Returns human-readable violations when `parentFolderID` and `parentFolder` diverge (DM-R1).
    func hierarchyViolations() throws -> [String] {
        let items = try fetchAllVaultItems(limit: 500)
        var violations: [String] = []
        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        for item in items {
            if let parentID = item.parentFolderID {
                if item.parentFolder?.id != parentID {
                    violations.append("\(item.id): parentFolder mismatch (id=\(parentID))")
                }
                if byID[parentID] == nil {
                    violations.append("\(item.id): orphan parentFolderID \(parentID)")
                }
            } else if item.parentFolder != nil {
                violations.append("\(item.id): parentFolder set without parentFolderID")
            }
        }
        return violations
    }

    /// Uppercase, collapsed whitespace — matches vault course-link writes.
    static func normalizedCourseCode(_ raw: String?) -> String? {
        let normalized = raw?
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        guard let normalized, !normalized.isEmpty else { return nil }
        return normalized
    }

    func deleteVaultDocument(id: UUID) throws {
        guard let document = try fetchDocument(id: id) else { return }
        if !document.isFolder, !document.localRelativePath.isEmpty,
           let url = urlForVaultRelativePath(document.localRelativePath) {
            try? FileManager.default.removeItem(at: url)
        }
        context.delete(document)
        ModelMergeCoalescer.scheduleSave(context)
    }

    func bulkDeleteVaultDocuments(ids: [UUID]) throws {
        for id in ids {
            try deleteVaultDocument(id: id)
        }
    }

    @discardableResult
    func createVaultFolder(name: String, parentFolderID: UUID?) throws -> VaultDocument? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let folder = VaultDocument(
            fileName: trimmed,
            category: VaultDocumentCategory.other.rawValue,
            localRelativePath: "",
            isFolder: true
        )
        folder.source = "vault"
        folder.parentFolderID = parentFolderID
        syncParentFolderRelationship(for: folder)
        context.insert(folder)
        ModelMergeCoalescer.scheduleSave(context)
        return folder
    }

    func renameVaultFolder(id: UUID, newName: String) throws {
        guard let folder = try fetchDocument(id: id), folder.isFolder else { return }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        folder.fileName = trimmed
        ModelMergeCoalescer.scheduleSave(context)
    }

    func deleteVaultFolder(id: UUID, includeContents: Bool) throws {
        guard let folder = try fetchDocument(id: id), folder.isFolder else { return }
        let allItems = try fetchAllVaultItems()

        if includeContents {
            var queue: [UUID] = [id]
            while let current = queue.popLast() {
                let children = allItems.filter { $0.parentFolderID == current }
                for child in children {
                    if child.isFolder { queue.append(child.id) }
                    if !child.isFolder, !child.localRelativePath.isEmpty,
                       let url = urlForVaultRelativePath(child.localRelativePath) {
                        try? FileManager.default.removeItem(at: url)
                    }
                    context.delete(child)
                }
            }
        } else {
            for child in allItems where child.parentFolderID == id {
                child.parentFolderID = folder.parentFolderID
                syncParentFolderRelationship(for: child)
            }
        }
        context.delete(folder)
        ModelMergeCoalescer.scheduleSave(context)
    }

    func moveVaultDocument(id: UUID, toFolderID folderID: UUID?) throws {
        guard let doc = try fetchDocument(id: id) else { return }
        doc.parentFolderID = folderID
        syncParentFolderRelationship(for: doc)
        ModelMergeCoalescer.scheduleSave(context)
    }

    func setVaultDocumentCourseLink(id: UUID, courseCode: String?) throws {
        guard let doc = try fetchDocument(id: id) else { return }
        doc.courseCodeLinked = Self.normalizedCourseCode(courseCode)
        ModelMergeCoalescer.scheduleSave(context)
    }

    @MainActor
    @discardableResult
    func addVaultDocument(
        fromSelectedURL url: URL,
        category: VaultDocumentCategory = .other,
        source: String = "vault",
        parentFolderID: UUID? = nil
    ) async throws -> VaultDocument {
        let fileName = url.lastPathComponent
        let plaintext = try await VaultSourceFileMaterializer.materializedDataAsync(from: url)
        let fileSize = Int64(plaintext.count)
        let vaultDir = try Self.documentVaultDirectoryURL()
        let id = UUID()
        let storedFileName = "\(id.uuidString)-\(fileName).colenc"
        let destination = vaultDir.appendingPathComponent(storedFileName)

        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }

        let stored = SecurityManager.shared.encryptBlobForStorage(plaintext) ?? plaintext
        try stored.write(to: destination, options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)

        let document = VaultDocument(
            id: id,
            fileName: fileName,
            category: category.rawValue,
            fileSizeBytes: fileSize,
            localRelativePath: storedFileName
        )
        document.source = source
        document.parentFolderID = parentFolderID
        syncParentFolderRelationship(for: document)
        context.insert(document)
        ModelMergeCoalescer.scheduleSave(context)
        return document
    }

    @MainActor
    func replaceVaultDocumentContent(documentID: UUID, fromSelectedURL url: URL) async throws {
        guard let document = try fetchDocument(id: documentID), !document.isFolder else { return }
        guard let storedURL = urlForVaultRelativePath(document.localRelativePath) else { return }

        let plaintext = try await VaultSourceFileMaterializer.materializedDataAsync(from: url)
        let stored = SecurityManager.shared.encryptBlobForStorage(plaintext) ?? plaintext
        try stored.write(to: storedURL, options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: storedURL.path)
        document.fileSizeBytes = Int64(plaintext.count)
        ModelMergeCoalescer.scheduleSave(context)
    }

    // MARK: - Watched folders

    func fetchWatchedFolder(id: UUID) throws -> WatchedFolder? {
        var descriptor = FetchDescriptor<WatchedFolder>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    @discardableResult
    func addWatchedFolder(path: String, bookmarkData: Data? = nil) throws -> WatchedFolder {
        let canonical = (path as NSString).standardizingPath
        var descriptor = FetchDescriptor<WatchedFolder>(
            predicate: #Predicate { $0.path == canonical }
        )
        descriptor.fetchLimit = 1
        if let existing = try context.fetch(descriptor).first {
            existing.isEnabled = true
            if let bookmarkData { existing.bookmarkData = bookmarkData }
            ModelMergeCoalescer.scheduleSave(context)
            return existing
        }

        let folder = WatchedFolder(path: canonical, bookmarkData: bookmarkData)
        context.insert(folder)
        ModelMergeCoalescer.scheduleSave(context)
        return folder
    }

    func removeWatchedFolder(id: UUID) throws {
        guard let folder = try fetchWatchedFolder(id: id) else { return }
        context.delete(folder)
        ModelMergeCoalescer.scheduleSave(context)
    }

    func updateWatchedFolderBookmark(id: UUID, bookmarkData: Data) throws {
        guard let folder = try fetchWatchedFolder(id: id) else { return }
        folder.bookmarkData = bookmarkData
        ModelMergeCoalescer.scheduleSave(context)
    }

    func hasMirroredVaultDocumentRows() throws -> Bool {
        var descriptor = FetchDescriptor<VaultDocument>()
        descriptor.fetchLimit = 1
        return try !context.fetch(descriptor).isEmpty
    }
}