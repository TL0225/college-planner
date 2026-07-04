// DataWipeManager.swift
// Feature: Core
// Purpose: Core module — DataWipeManager.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import AppKit

/// High-impact operation: delete all local app data and exit.
///
/// Triggers an app restart requirement because persistence stacks and in-memory
/// objects cannot be safely reset in-place without risk of inconsistency.
enum DataWipeManager {
    @MainActor
    static func wipeAllDataAndExit() throws {
        try wipeAllDataAndExit(persistence: CollegePersistence.shared)
    }

    @MainActor
    static func wipeAllDataAndExit(persistence: CollegePersistence) throws {
        let fm = FileManager.default

        GoogleAuthService.shared.signOut()
        KeychainMasterKey.deleteMasterKey()
        LMSKeychainService.shared.deleteAll()

        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
            UserDefaults.standard.synchronize()
        }

        ModelStoreMaintenance.removeAllOnDiskStores()

        let appSupport = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false)

        // Legacy local store sqlite files (safe to delete after local store cutover).
        let legacyFilenames = [
            "CollegeDataModel.sqlite",
            "CollegeProfile.sqlite",
            "CollegeCatalog.sqlite",
        ]
        for name in legacyFilenames {
            let url = appSupport.appendingPathComponent(name)
            try removeSQLiteBundleIfPresent(at: url, fileManager: fm)
        }
        let legacyCollegeDir = appSupport.appendingPathComponent("College", isDirectory: true)
        for name in legacyFilenames {
            let url = legacyCollegeDir.appendingPathComponent(name)
            try removeSQLiteBundleIfPresent(at: url, fileManager: fm)
        }

        let vaultDir = appSupport.appendingPathComponent("College/DocumentVault", isDirectory: true)
        if fm.fileExists(atPath: vaultDir.path) {
            try fm.removeItem(at: vaultDir)
        }

        DiagnosticsArtifacts.wipeAllArtifacts()

        let tempDec = fm.temporaryDirectory.appendingPathComponent("College-DecryptedVault", isDirectory: true)
        if fm.fileExists(atPath: tempDec.path) {
            try fm.removeItem(at: tempDec)
        }

        _ = persistence
        NSApplication.shared.terminate(nil)
    }

    private static func removeSQLiteBundleIfPresent(at url: URL, fileManager fm: FileManager) throws {
        guard fm.fileExists(atPath: url.path) else { return }
        try fm.removeItem(at: url)
        for suffix in ["-wal", "-shm"] {
            let sidecar = URL(fileURLWithPath: url.path + suffix)
            if fm.fileExists(atPath: sidecar.path) {
                try fm.removeItem(at: sidecar)
            }
        }
    }
}
