import Foundation
import CoreData
import AppKit

/// High-impact operation: delete all local app data and exit.
///
/// This intentionally triggers an app restart requirement, because Core Data stacks and in-memory
/// objects cannot be safely reset in-place in a complex app without risk of inconsistency.
enum DataWipeManager {
    @MainActor
    static func wipeAllDataAndExit() throws {
        try wipeAllDataAndExit(coreData: CoreDataManager.shared)
    }

    @MainActor
    static func wipeAllDataAndExit(coreData: CoreDataManager) throws {
        let fm = FileManager.default

        // 1) Sign out / revoke local auth tokens (best-effort).
        GoogleAuthService.shared.signOut()

        // 2) Delete the master encryption key (locks any remaining encrypted blobs).
        KeychainMasterKey.deleteMasterKey()

        // 3) Clear UserDefaults domain.
        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
            UserDefaults.standard.synchronize()
        }

        // 4) Remove Core Data stores (sqlite + -wal + -shm).
        let coordinator = coreData.container.persistentStoreCoordinator
        let stores = coordinator.persistentStores
        for store in stores {
            if let url = store.url {
                try? coordinator.remove(store)
                try? coordinator.destroyPersistentStore(at: url, ofType: NSSQLiteStoreType, options: nil)
                try? fm.removeItem(at: url)
                try? fm.removeItem(at: url.appendingPathExtension("-wal"))
                try? fm.removeItem(at: url.appendingPathExtension("-shm"))
            }
        }

        // 5) Remove Document Vault + Logs directories (best-effort).
        let appSupport = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        let vaultDir = appSupport.appendingPathComponent("College/DocumentVault", isDirectory: true)
        try? fm.removeItem(at: vaultDir)

        let bundleID = Bundle.main.bundleIdentifier ?? "College"
        let logsDir = appSupport.appendingPathComponent(bundleID, isDirectory: true).appendingPathComponent("Logs", isDirectory: true)
        try? fm.removeItem(at: logsDir)

        // 6) Remove temporary decrypted vault directory.
        let tempDec = fm.temporaryDirectory.appendingPathComponent("College-DecryptedVault", isDirectory: true)
        try? fm.removeItem(at: tempDec)

        // 7) Exit (restart required).
        NSApplication.shared.terminate(nil)
    }
}

