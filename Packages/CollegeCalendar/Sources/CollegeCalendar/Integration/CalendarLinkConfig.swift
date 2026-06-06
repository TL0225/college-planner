// CalendarLinkConfig.swift
// Feature: Calendar
// Purpose: Calendar module — CalendarLinkConfig.
// Data: CollegePersistence / repositories when applicable.

import Foundation

/// Persisted mapping after connecting a provider calendar (mirror vs app calendar).
struct CalendarLinkConfig: Codable, Equatable, Identifiable {
    enum Mode: String, Codable {
        case mirrorProvider
        case mapToAppCalendar
    }

    var id: String { providerCalendarID }
    let providerCalendarID: String
    let providerSource: String
    var mode: Mode
    var appCalendarID: String?
    var displayName: String?
    var colorHex: String?

    static let storageKey = "calendar.linkConfigs.v1"

    static func loadAll() -> [CalendarLinkConfig] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([CalendarLinkConfig].self, from: data)
        else { return [] }
        return decoded
    }

    static func saveAll(_ configs: [CalendarLinkConfig]) {
        guard let data = try? JSONEncoder().encode(configs) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
