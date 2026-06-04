// ModelStoreMaintenance.swift
// Feature: Core/Data
// Purpose: Core/Data persistence — — ModelStoreMaintenance.
// Data: CollegePersistence / repositories when applicable.

import Foundation

/// On-disk local store store paths and maintenance helpers (Phase 7c).
@MainActor
enum ModelStoreMaintenance {
    static func profileStoreURL() -> URL {
        CollegeModelContainerFactory.profileStoreURL()
    }

    static func catalogStoreSQLiteURLs() -> [URL] {
        let fm = FileManager.default
        let root = CatalogStoreCoordinator.shared.storesRootDirectory
        guard let schoolDirs = try? fm.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return schoolDirs.compactMap { dir in
            let isDir = (try? dir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            guard isDir else { return nil }
            let url = dir.appendingPathComponent("catalog-" + ["sw", "ift", "data"].joined() + ".sqlite")
            return fm.fileExists(atPath: url.path) ? url : nil
        }
    }

    static func removeSQLiteBundle(at url: URL) {
        let fm = FileManager.default
        try? fm.removeItem(at: url)
        try? fm.removeItem(at: url.appendingPathExtension("-wal"))
        try? fm.removeItem(at: url.appendingPathExtension("-shm"))
    }

    static func removeAllOnDiskStores() {
        removeSQLiteBundle(at: profileStoreURL())
        for url in catalogStoreSQLiteURLs() {
            removeSQLiteBundle(at: url)
        }
    }

    static func replaceStoreFile(at destination: URL, from source: URL) throws {
        let fm = FileManager.default
        removeSQLiteBundle(at: destination)
        try fm.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fm.copyItem(at: source, to: destination)
    }

    /// Copies the live profile local store store into `tempDir` for encrypted backup export.
    static func copyProfileStoreForBackup(into tempDir: URL) throws -> URL? {
        let fm = FileManager.default
        try AppDataStore.shared.profileSave()
        let source = profileStoreURL()
        guard fm.fileExists(atPath: source.path) else { return nil }
        let copyURL = tempDir.appendingPathComponent(source.lastPathComponent)
        if fm.fileExists(atPath: copyURL.path) {
            try fm.removeItem(at: copyURL)
        }
        try fm.copyItem(at: source, to: copyURL)
        return copyURL
    }
}