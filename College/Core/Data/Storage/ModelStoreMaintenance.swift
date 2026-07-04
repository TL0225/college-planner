// ModelStoreMaintenance.swift
// Feature: Core/Data
// Purpose: Core/Data persistence — — ModelStoreMaintenance.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftData

/// On-disk local store store paths and maintenance helpers (Phase 7c).
@MainActor
enum ModelStoreMaintenance {
    static func profileStoreURL() -> URL {
        CollegeModelContainerFactory.profileStoreURL()
    }

    static func catalogStoreSQLiteURLs() -> [URL] {
        let fm = FileManager.default
        let root = CollegeModelContainerFactory.catalogStoresRootURL()
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
            let url = CollegeModelContainerFactory.catalogStoreURL(for: dir.lastPathComponent)
            return fm.fileExists(atPath: url.path) ? url : nil
        }
    }

    static func legacyCatalogSQLiteURLs() -> [URL] {
        let fm = FileManager.default
        let root = CollegeModelContainerFactory.catalogStoresRootURL()
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
            let url = dir.appendingPathComponent("catalog.sqlite")
            return fm.fileExists(atPath: url.path) ? url : nil
        }
    }

    static func removeSQLiteBundle(at url: URL) {
        let fm = FileManager.default
        try? fm.removeItem(at: url)
        try? fm.removeItem(at: url.appendingPathExtension("-wal"))
        try? fm.removeItem(at: url.appendingPathExtension("-shm"))
    }

    /// Moves an unopenable profile store aside so launch can create a fresh `College.sqlite`.
    @discardableResult
    static func quarantineProfileStore(at url: URL = profileStoreURL()) -> URL? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return nil }

        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let quarantineURL = url.deletingLastPathComponent()
            .appendingPathComponent("College.sqlite.unopenable-\(stamp)")

        do {
            try fm.moveItem(at: url, to: quarantineURL)
            for suffix in ["-wal", "-shm"] {
                let sidecar = URL(fileURLWithPath: url.path + suffix)
                guard fm.fileExists(atPath: sidecar.path) else { continue }
                try fm.moveItem(at: sidecar, to: URL(fileURLWithPath: quarantineURL.path + suffix))
            }
            return quarantineURL
        } catch {
            return nil
        }
    }

    static func removeAllOnDiskStores() {
        removeSQLiteBundle(at: profileStoreURL())
        removeSQLiteBundle(at: CollegeModelContainerFactory.legacyProfileStoreURL())
        for url in catalogStoreSQLiteURLs() + legacyCatalogSQLiteURLs() {
            removeSQLiteBundle(at: url)
        }
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        try? FileManager.default.removeItem(at: appSupport.appendingPathComponent("College/catalog-stores-migrated"))
        let registryURL = CollegeModelContainerFactory.catalogStoresRootURL()
            .appendingPathComponent("registry.json")
        if FileManager.default.fileExists(atPath: registryURL.path) {
            try? FileManager.default.removeItem(at: registryURL)
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
        try finalizeProfileStoreForBackup()
        try AppDataStore.shared.profileSave()
        let source = profileStoreURL()
        guard fm.fileExists(atPath: source.path) else { return nil }
        let copyURL = tempDir.appendingPathComponent(source.lastPathComponent)
        if fm.fileExists(atPath: copyURL.path) {
            try fm.removeItem(at: copyURL)
        }
        try fm.copyItem(at: source, to: copyURL)
        for suffix in ["-wal", "-shm"] {
            let sidecar = URL(fileURLWithPath: source.path + suffix)
            guard fm.fileExists(atPath: sidecar.path) else { continue }
            try fm.copyItem(at: sidecar, to: URL(fileURLWithPath: copyURL.path + suffix))
        }
        return copyURL
    }

    /// Opens the on-disk profile store so WAL sidecars are checkpointed before backup copy.
    @MainActor
    static func finalizeProfileStoreForBackup() throws {
        let container = try CollegeModelContainerFactory.makeProfileContainer()
        if container.mainContext.hasChanges {
            try container.mainContext.save()
        }
    }
}