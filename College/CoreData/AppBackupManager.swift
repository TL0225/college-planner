import Foundation
import CoreData
import CryptoKit

/// One-file export/import of app state:
/// - Core Data SQLite store (copy via `replacePersistentStore` to ensure consistency)
/// - App UserDefaults persistent domain (bundle identifier)
///
/// Notes:
/// - Does NOT include Keychain secrets (OAuth tokens).
/// - Import replaces the Core Data store on disk; app restart is recommended.
enum AppBackupManager {
    enum BackupError: Error {
        case missingBundleIdentifier
        case missingPersistentStoreURL
        case invalidBackupFile
        case appLocked
    }

    // Simple file format (single file, no external zip lib):
    // [8 bytes magic] [8 bytes settingsLen] [settings bytes] [8 bytes storeLen] [store bytes]
    private static let magicV1 = Data("COLBKUP1".utf8)

    // Encrypted format (COLBKUP2):
    // [8 bytes magic] [8 bytes settingsBoxLen] [settings sealedbox bytes] [storeChunkRecords...]
    // storeChunkRecord: [4 bytes chunkIndex] [4 bytes sealedboxLen] [sealedbox bytes]
    // - Each sealed box is AES-GCM with AAD = magic + chunkIndex (prevents reordering).
    private static let magicV2 = Data("COLBKUP2".utf8)

    @MainActor
    static func exportBackup(to destinationURL: URL, coreData: CoreDataManager = .shared) throws {
        let fm = FileManager.default
        guard let bundleID = Bundle.main.bundleIdentifier else { throw BackupError.missingBundleIdentifier }

        guard let key = SecurityManager.shared.masterKey else {
            throw BackupError.appLocked
        }

        let coordinator = coreData.container.persistentStoreCoordinator
        guard let store = coordinator.persistentStores.first, let storeURL = store.url else {
            throw BackupError.missingPersistentStoreURL
        }

        // Extract app domain defaults (not global/system keys).
        let defaultsDomain = UserDefaults.standard.persistentDomain(forName: bundleID) ?? [:]
        let settingsData = try PropertyListSerialization.data(
            fromPropertyList: defaultsDomain,
            format: .xml,
            options: 0
        )

        // Create a consistent store copy using Core Data itself.
        let tempDir = fm.temporaryDirectory.appendingPathComponent("CollegeBackup-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDir) }

        let storeCopyURL = tempDir.appendingPathComponent("coredata.sqlite")
        try coordinator.replacePersistentStore(
            at: storeCopyURL,
            destinationOptions: nil,
            withPersistentStoreFrom: storeURL,
            sourceOptions: nil,
            ofType: NSSQLiteStoreType
        )

        // Build a single ENCRYPTED backup file (chunked, avoids loading large stores into RAM).
        fm.createFile(atPath: destinationURL.path, contents: nil)
        let out = try FileHandle(forWritingTo: destinationURL)
        defer { try? out.close() }

        try out.write(contentsOf: magicV2)

        // Encrypt settings block.
        let settingsBox = try sealChunk(settingsData, using: key, chunkIndex: 0xFFFF_FFFE)
        try out.write(contentsOf: UInt64(settingsBox.count).littleEndianData)
        try out.write(contentsOf: settingsBox)

        // Encrypt store as chunk records.
        let storeSize = (try? storeCopyURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let storeIn = try FileHandle(forReadingFrom: storeCopyURL)
        defer { try? storeIn.close() }

        var remaining = storeSize
        var index: UInt32 = 0
        while remaining > 0 {
            let toRead = min(1_048_576, remaining)
            let chunk = try storeIn.read(upToCount: toRead) ?? Data()
            if chunk.isEmpty { throw BackupError.invalidBackupFile }

            let box = try sealChunk(chunk, using: key, chunkIndex: index)
            try out.write(contentsOf: index.littleEndianData)
            try out.write(contentsOf: UInt32(box.count).littleEndianData)
            try out.write(contentsOf: box)

            remaining -= chunk.count
            index &+= 1
        }
    }

    @MainActor
    static func importBackup(from sourceURL: URL, coreData: CoreDataManager = .shared) throws {
        let fm = FileManager.default
        guard let bundleID = Bundle.main.bundleIdentifier else { throw BackupError.missingBundleIdentifier }

        guard let key = SecurityManager.shared.masterKey else {
            throw BackupError.appLocked
        }

        let coordinator = coreData.container.persistentStoreCoordinator
        guard let store = coordinator.persistentStores.first, let storeURL = store.url else {
            throw BackupError.missingPersistentStoreURL
        }

        let tempDir = fm.temporaryDirectory.appendingPathComponent("CollegeRestore-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDir) }

        let extractedStoreURL = tempDir.appendingPathComponent("coredata.sqlite")

        let fh = try FileHandle(forReadingFrom: sourceURL)
        defer { try? fh.close() }

        let magicLen = magicV2.count
        let readMagic = try fh.read(upToCount: magicLen) ?? Data()

        if readMagic == magicV1 {
            // Legacy plaintext backup support (COLBKUP1).
            func readUInt64() throws -> UInt64 {
                let d = try fh.read(upToCount: 8) ?? Data()
                guard d.count == 8 else { throw BackupError.invalidBackupFile }
                return UInt64(littleEndianData: d)
            }

            let settingsLen = Int(try readUInt64())
            guard settingsLen >= 0 else { throw BackupError.invalidBackupFile }
            let settingsData = try fh.read(upToCount: settingsLen) ?? Data()
            guard settingsData.count == settingsLen else { throw BackupError.invalidBackupFile }

            let storeLen = Int(try readUInt64())
            guard storeLen >= 0 else { throw BackupError.invalidBackupFile }

            fm.createFile(atPath: extractedStoreURL.path, contents: nil)
            let storeOut = try FileHandle(forWritingTo: extractedStoreURL)
            defer { try? storeOut.close() }

            var remaining = storeLen
            while remaining > 0 {
                let chunk = try fh.read(upToCount: min(1_048_576, remaining)) ?? Data()
                if chunk.isEmpty { break }
                try storeOut.write(contentsOf: chunk)
                remaining -= chunk.count
            }
            guard remaining == 0 else { throw BackupError.invalidBackupFile }

            // Restore defaults domain first.
            let plist = try PropertyListSerialization.propertyList(from: settingsData, options: [], format: nil)
            if let dict = plist as? [String: Any] {
                UserDefaults.standard.removePersistentDomain(forName: bundleID)
                UserDefaults.standard.setPersistentDomain(dict, forName: bundleID)
                UserDefaults.standard.synchronize()
            }
        } else if readMagic == magicV2 {
            func readUInt64() throws -> UInt64 {
                let d = try fh.read(upToCount: 8) ?? Data()
                guard d.count == 8 else { throw BackupError.invalidBackupFile }
                return UInt64(littleEndianData: d)
            }

            func readUInt32() throws -> UInt32 {
                let d = try fh.read(upToCount: 4) ?? Data()
                guard d.count == 4 else { throw BackupError.invalidBackupFile }
                return UInt32(littleEndianData: d)
            }

            let settingsBoxLen = Int(try readUInt64())
            guard settingsBoxLen >= 0 else { throw BackupError.invalidBackupFile }
            let settingsBox = try fh.read(upToCount: settingsBoxLen) ?? Data()
            guard settingsBox.count == settingsBoxLen else { throw BackupError.invalidBackupFile }
            let settingsData = try openChunk(settingsBox, using: key, chunkIndex: 0xFFFF_FFFE)

            // Restore defaults domain first.
            let plist = try PropertyListSerialization.propertyList(from: settingsData, options: [], format: nil)
            if let dict = plist as? [String: Any] {
                UserDefaults.standard.removePersistentDomain(forName: bundleID)
                UserDefaults.standard.setPersistentDomain(dict, forName: bundleID)
                UserDefaults.standard.synchronize()
            }

            // Stream-decrypt store chunk records.
            fm.createFile(atPath: extractedStoreURL.path, contents: nil)
            let storeOut = try FileHandle(forWritingTo: extractedStoreURL)
            defer { try? storeOut.close() }

            while true {
                // Attempt to read a chunk header; EOF means we're done.
                let idxData = try fh.read(upToCount: 4) ?? Data()
                if idxData.isEmpty { break }
                guard idxData.count == 4 else { throw BackupError.invalidBackupFile }
                let chunkIndex = UInt32(littleEndianData: idxData)
                let boxLen = Int(try readUInt32())
                guard boxLen >= 0 else { throw BackupError.invalidBackupFile }
                let box = try fh.read(upToCount: boxLen) ?? Data()
                guard box.count == boxLen else { throw BackupError.invalidBackupFile }

                let plaintext = try openChunk(box, using: key, chunkIndex: chunkIndex)
                try storeOut.write(contentsOf: plaintext)
            }
        } else {
            throw BackupError.invalidBackupFile
        }

        // Replace the existing persistent store with the restored one.
        // Note: this changes the store file on disk; a restart is recommended.
        try coordinator.replacePersistentStore(
            at: storeURL,
            destinationOptions: nil,
            withPersistentStoreFrom: extractedStoreURL,
            sourceOptions: nil,
            ofType: NSSQLiteStoreType
        )

        // Best-effort: drop any stale managed object graph.
        coreData.viewContext.reset()
    }

    // MARK: - Crypto helpers

    private static func aad(for chunkIndex: UInt32) -> Data {
        magicV2 + chunkIndex.littleEndianData
    }

    private static func sealChunk(_ data: Data, using key: SymmetricKey, chunkIndex: UInt32) throws -> Data {
        let sealed = try AES.GCM.seal(data, using: key, authenticating: aad(for: chunkIndex))
        guard let combined = sealed.combined else { throw BackupError.invalidBackupFile }
        return combined
    }

    private static func openChunk(_ combined: Data, using key: SymmetricKey, chunkIndex: UInt32) throws -> Data {
        let box = try AES.GCM.SealedBox(combined: combined)
        return try AES.GCM.open(box, using: key, authenticating: aad(for: chunkIndex))
    }
}

private extension UInt64 {
    var littleEndianData: Data {
        var v = self.littleEndian
        return Data(bytes: &v, count: MemoryLayout<UInt64>.size)
    }

    init(littleEndianData data: Data) {
        var v: UInt64 = 0
        withUnsafeMutableBytes(of: &v) { dst in
            dst.copyBytes(from: data.prefix(8))
        }
        self = UInt64(littleEndian: v)
    }
}

private extension UInt32 {
    var littleEndianData: Data {
        var v = self.littleEndian
        return Data(bytes: &v, count: MemoryLayout<UInt32>.size)
    }

    init(littleEndianData data: Data) {
        var v: UInt32 = 0
        withUnsafeMutableBytes(of: &v) { dst in
            dst.copyBytes(from: data.prefix(4))
        }
        self = UInt32(littleEndian: v)
    }
}

