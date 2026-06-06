// CalendarSyncMapDiskPersistence.swift
// Feature: Calendar
// Purpose: Calendar module — CalendarSyncMapDiskPersistence.
// Data: CollegePersistence / repositories when applicable.

import Foundation

/// Persists large `[String: String]` calendar sync maps under Application Support.
/// macOS CFPreferences rejects single-domain writes approaching ~4 MiB; unbounded
/// event ID maps must not live in `UserDefaults`.
enum CalendarSyncMapDiskPersistence {
    private static let folderName = "Timothy.College"

    static func directoryURL() -> URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return root.appendingPathComponent(folderName, isDirectory: true)
    }

    static func fileURL(fileName: String) -> URL {
        directoryURL().appendingPathComponent(fileName, isDirectory: false)
    }

    static func loadMap(fileName: String) async -> [String: String]? {
        await Task.detached(priority: .utility) {
            loadMapSync(fileName: fileName)
        }.value
    }

    static func loadMapSync(fileName: String) -> [String: String]? {
        let url = fileURL(fileName: fileName)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode([String: String].self, from: data)
    }

    static func persistMap(_ map: [String: String], fileName: String, legacyUserDefaultsKey: String?) async {
        await Task.detached(priority: .utility) {
            persistMapSync(map, fileName: fileName, legacyUserDefaultsKey: legacyUserDefaultsKey)
        }.value
    }

    static func persistMapSync(_ map: [String: String], fileName: String, legacyUserDefaultsKey: String?) {
        do {
            try FileManager.default.createDirectory(at: directoryURL(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(map)
            let url = fileURL(fileName: fileName)
            let tmpURL = url.appendingPathExtension("tmp")
            try data.write(to: tmpURL, options: .atomic)
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            try FileManager.default.moveItem(at: tmpURL, to: url)
            if let legacyUserDefaultsKey {
                UserDefaults.standard.removeObject(forKey: legacyUserDefaultsKey)
            }
        } catch {
            #if DEBUG
            print("CalendarSyncMapDiskPersistence.persistMap failed (\(fileName)): \(error)")
            #endif
        }
    }

    /// If JSON already exists, drops legacy UserDefaults. Otherwise migrates a plist dictionary to disk.
    static func migrateFromUserDefaultsIfNeeded(legacyKey: String, fileName: String) {
        let ud = UserDefaults.standard
        if loadMapSync(fileName: fileName) != nil {
            if ud.object(forKey: legacyKey) != nil {
                ud.removeObject(forKey: legacyKey)
            }
            return
        }
        guard let legacy = ud.dictionary(forKey: legacyKey) as? [String: String], !legacy.isEmpty else {
            return
        }
        persistMapSync(legacy, fileName: fileName, legacyUserDefaultsKey: legacyKey)
    }
}
