// LocationRecentsStore.swift
// Feature: Core
// Purpose: Core module — LocationRecentsStore.
// Data: CollegePersistence / repositories when applicable.

import Foundation

enum LocationRecentsStore {
    private static let key = "College.RecentLocations.v1"
    private static let maxCount = 12

    @MainActor
    static func load() -> [ResolvedLocation] {
        guard let stored = UserDefaults.standard.data(forKey: key) else { return [] }
        let data = SecurityManager.shared.decryptBlobFromStorage(stored) ?? stored
        return (try? JSONDecoder().decode([ResolvedLocation].self, from: data)) ?? []
    }

    @MainActor
    static func save(_ locations: [ResolvedLocation]) {
        guard let data = try? JSONEncoder().encode(Array(locations.prefix(maxCount))) else { return }
        let stored = SecurityManager.shared.encryptBlobForStorage(data) ?? data
        UserDefaults.standard.set(stored, forKey: key)
    }

    @MainActor
    static func add(_ location: ResolvedLocation) {
        var existing = load()

        // Deduplicate by title+subtitle+coordinate (id is ephemeral).
        existing.removeAll { item in
            item.title == location.title && item.subtitle == location.subtitle && item.latitude == location.latitude && item.longitude == location.longitude
        }
        existing.insert(location, at: 0)
        save(existing)
    }
}
