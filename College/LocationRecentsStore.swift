import Foundation

enum LocationRecentsStore {
    private static let key = "College.RecentLocations.v1"
    private static let maxCount = 12

    static func load() -> [ResolvedLocation] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([ResolvedLocation].self, from: data)) ?? []
    }

    static func save(_ locations: [ResolvedLocation]) {
        guard let data = try? JSONEncoder().encode(Array(locations.prefix(maxCount))) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

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
