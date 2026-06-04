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
            try? fm.removeItem(at: url)
            try? fm.removeItem(at: url.appendingPathExtension("-wal"))
            try? fm.removeItem(at: url.appendingPathExtension("-shm"))
        }
        let legacyCollegeDir = appSupport.appendingPathComponent("College", isDirectory: true)
        for name in legacyFilenames {
            let url = legacyCollegeDir.appendingPathComponent(name)
            try? fm.removeItem(at: url)
            try? fm.removeItem(at: url.appendingPathExtension("-wal"))
            try? fm.removeItem(at: url.appendingPathExtension("-shm"))
        }

        let vaultDir = appSupport.appendingPathComponent("College/DocumentVault", isDirectory: true)
        try? fm.removeItem(at: vaultDir)

        let bundleID = Bundle.main.bundleIdentifier ?? "College"
        let logsDir = appSupport.appendingPathComponent(bundleID, isDirectory: true).appendingPathComponent("Logs", isDirectory: true)
        try? fm.removeItem(at: logsDir)

        let tempDec = fm.temporaryDirectory.appendingPathComponent("College-DecryptedVault", isDirectory: true)
        try? fm.removeItem(at: tempDec)

        _ = persistence
        NSApplication.shared.terminate(nil)
    }
}
