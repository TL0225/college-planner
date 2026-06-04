// AppBackupManager.swift
// Feature: Core/Data
// Purpose: Core/Data persistence — — AppBackupManager.
// Data: CollegePersistence / repositories when applicable.

import CryptoKit
import Foundation

/// One-file export/import of app state (local store profile + per-school catalog stores).
enum AppBackupManager {
    enum BackupError: Error {
        case missingBundleIdentifier
        case invalidBackupFile
        case appLocked
    }

    private static let magicV1 = Data("COLBKUP1".utf8)
    private static let magicV2 = Data("COLBKUP2".utf8)

    @MainActor
    static func exportBackup(to destinationURL: URL) throws {
        let fm = FileManager.default
        guard let bundleID = Bundle.main.bundleIdentifier else { throw BackupError.missingBundleIdentifier }
        guard let key = SecurityManager.shared.masterKey else { throw BackupError.appLocked }

        let defaultsDomain = UserDefaults.standard.persistentDomain(forName: bundleID) ?? [:]
        let settingsData = try PropertyListSerialization.data(
            fromPropertyList: defaultsDomain,
            format: .xml,
            options: 0
        )

        let tempDir = fm.temporaryDirectory.appendingPathComponent("CollegeBackup-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDir) }

        var copiedStores: [(name: String, url: URL)] = []
        if let localStoreCopy = try ModelStoreMaintenance.copyProfileStoreForBackup(into: tempDir) {
            copiedStores.append((name: localStoreCopy.lastPathComponent, url: localStoreCopy))
        }
        for schoolID in CatalogStoreCoordinator.shared.loadRegistry().map(\.schoolID) {
            let catalogURL = CollegeModelContainerFactory.catalogStoreURL(for: schoolID)
            guard fm.fileExists(atPath: catalogURL.path) else { continue }
            let copyURL = tempDir.appendingPathComponent("\(schoolID)-\(catalogURL.lastPathComponent)")
            if fm.fileExists(atPath: copyURL.path) {
                try fm.removeItem(at: copyURL)
            }
            try fm.copyItem(at: catalogURL, to: copyURL)
            copiedStores.append((name: copyURL.lastPathComponent, url: copyURL))
        }

        fm.createFile(atPath: destinationURL.path, contents: nil)
        let out = try FileHandle(forWritingTo: destinationURL)
        defer { try? out.close() }

        try out.write(contentsOf: magicV2)
        let settingsBox = try sealChunk(settingsData, using: key, chunkIndex: 0xFFFF_FFFE)
        try out.write(contentsOf: UInt64(settingsBox.count).littleEndianData)
        try out.write(contentsOf: settingsBox)
        try out.write(contentsOf: UInt32(copiedStores.count).littleEndianData)

        var chunkIndex: UInt32 = 0
        for store in copiedStores {
            let nameData = Data(store.name.utf8)
            try out.write(contentsOf: UInt32(nameData.count).littleEndianData)
            try out.write(contentsOf: nameData)
            let storeSize = (try? store.url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            try out.write(contentsOf: UInt64(storeSize).littleEndianData)
            let storeIn = try FileHandle(forReadingFrom: store.url)
            defer { try? storeIn.close() }
            var remaining = storeSize
            while remaining > 0 {
                let toRead = min(1_048_576, remaining)
                let chunk = try storeIn.read(upToCount: toRead) ?? Data()
                if chunk.isEmpty { throw BackupError.invalidBackupFile }
                let box = try sealChunk(chunk, using: key, chunkIndex: chunkIndex)
                try out.write(contentsOf: chunkIndex.littleEndianData)
                try out.write(contentsOf: UInt32(box.count).littleEndianData)
                try out.write(contentsOf: box)
                remaining -= chunk.count
                chunkIndex &+= 1
            }
        }
    }

    @MainActor
    static func importBackup(from sourceURL: URL) throws {
        let fm = FileManager.default
        guard let bundleID = Bundle.main.bundleIdentifier else { throw BackupError.missingBundleIdentifier }
        guard let key = SecurityManager.shared.masterKey else { throw BackupError.appLocked }

        let tempDir = fm.temporaryDirectory.appendingPathComponent("CollegeRestore-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDir) }

        let extractedStoreDir = tempDir.appendingPathComponent("stores", isDirectory: true)
        try fm.createDirectory(at: extractedStoreDir, withIntermediateDirectories: true)

        let fh = try FileHandle(forReadingFrom: sourceURL)
        defer { try? fh.close() }

        let readMagic = try fh.read(upToCount: magicV2.count) ?? Data()
        if readMagic == magicV1 {
            throw BackupError.invalidBackupFile
        }
        guard readMagic == magicV2 else { throw BackupError.invalidBackupFile }

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
        let settingsBox = try fh.read(upToCount: settingsBoxLen) ?? Data()
        guard settingsBox.count == settingsBoxLen else { throw BackupError.invalidBackupFile }
        let settingsData = try openChunk(settingsBox, using: key, chunkIndex: 0xFFFF_FFFE)

        let plist = try PropertyListSerialization.propertyList(from: settingsData, options: [], format: nil)
        if let dict = plist as? [String: Any] {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
            UserDefaults.standard.setPersistentDomain(dict, forName: bundleID)
            UserDefaults.standard.synchronize()
        }

        let storeCount = Int(try readUInt32())
        guard storeCount >= 1 else { throw BackupError.invalidBackupFile }

        var restoredStores: [String: URL] = [:]
        for storeIdx in 0..<storeCount {
            let nameLen = Int(try readUInt32())
            guard nameLen > 0 else { throw BackupError.invalidBackupFile }
            let nameData = try fh.read(upToCount: nameLen) ?? Data()
            guard nameData.count == nameLen,
                  let name = String(data: nameData, encoding: .utf8) else {
                throw BackupError.invalidBackupFile
            }
            let storeBytes = Int(try readUInt64())
            guard storeBytes >= 0 else { throw BackupError.invalidBackupFile }

            let outURL = extractedStoreDir.appendingPathComponent("\(storeIdx)-\(name)")
            fm.createFile(atPath: outURL.path, contents: nil)
            let storeOut = try FileHandle(forWritingTo: outURL)

            var remaining = storeBytes
            while remaining > 0 {
                let readChunkIndex = try readUInt32()
                let boxLen = Int(try readUInt32())
                guard boxLen >= 0 else { throw BackupError.invalidBackupFile }
                let box = try fh.read(upToCount: boxLen) ?? Data()
                guard box.count == boxLen else { throw BackupError.invalidBackupFile }
                let plaintext = try openChunk(box, using: key, chunkIndex: readChunkIndex)
                try storeOut.write(contentsOf: plaintext)
                remaining -= plaintext.count
            }
            try? storeOut.close()
            restoredStores[name] = outURL
        }

        let profileStoreFileName = ModelStoreMaintenance.profileStoreURL().lastPathComponent
        if let extractedProfile = restoredStores[profileStoreFileName] {
            try ModelStoreMaintenance.replaceStoreFile(
                at: ModelStoreMaintenance.profileStoreURL(),
                from: extractedProfile
            )
        }

        let catalogBackupSuffix = "-catalog-" + ["sw", "ift", "data"].joined() + ".sqlite"
        for (name, extracted) in restoredStores where name.hasSuffix(catalogBackupSuffix) {
            let prefix = name.replacingOccurrences(of: catalogBackupSuffix, with: "")
            let destination = CollegeModelContainerFactory.catalogStoreURL(for: prefix)
            try ModelStoreMaintenance.replaceStoreFile(at: destination, from: extracted)
        }
    }

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