// VaultRepository+FileIO.swift
// Feature: Core/Data
// Purpose: Core/Data persistence — — VaultDocumentCategory.
// Data: CollegePersistence / repositories when applicable.

import Foundation

// MARK: - Vault on-disk paths (Phase 7f)

extension VaultRepository {
    enum VaultDocumentCategory: String, Sendable {
        case syllabi = "Syllabi"
        case transcripts = "Transcripts"
        case calendar = "Calendar"
        case careerResume = "Career Resume"
        case other = "Other"
    }

    static func documentVaultDirectoryURL() throws -> URL {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = appSupport.appendingPathComponent("College/DocumentVault", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func decryptedVaultTempDirectoryURL() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("College-DecryptedVault", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func urlForVaultRelativePath(_ relativePath: String) -> URL? {
        let rel = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rel.isEmpty else { return nil }
        return (try? Self.documentVaultDirectoryURL())?.appendingPathComponent(rel)
    }

    func decryptedTempURLForStoredRelativePath(_ relativePath: String, displayFileName: String) -> URL? {
        guard let storedURL = urlForVaultRelativePath(relativePath) else { return nil }
        let stored: Data
        do {
            stored = try Data(contentsOf: storedURL)
        } catch {
            return nil
        }
        guard BlobCrypto.isEncryptedBlob(stored) else { return storedURL }
        guard let plaintext = SecurityManager.shared.decryptBlobFromStorage(stored) else { return nil }
        let tempDir = Self.decryptedVaultTempDirectoryURL()
        let name = displayFileName.isEmpty ? "Document" : displayFileName
        let tempURL = tempDir.appendingPathComponent("\(UUID().uuidString)-\(name)")
        do {
            try plaintext.write(to: tempURL, options: [.atomic])
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tempURL.path)
            return tempURL
        } catch {
            return nil
        }
    }
}