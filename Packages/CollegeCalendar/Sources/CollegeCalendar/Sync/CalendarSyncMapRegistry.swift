// CalendarSyncMapRegistry.swift
// Feature: Calendar
// Purpose: Calendar module — CalendarSyncMapRegistry.
// Data: CollegePersistence / repositories when applicable.

import Foundation

/// Namespaced on-disk sync maps (`providerID` + remote id → local UUID).
enum CalendarSyncMapRegistry {
    enum Namespace: String, Sendable {
        case apple
        case google
        case outlook
        case icloud
    }

    static func fileName(for namespace: Namespace) -> String {
        "\(namespace.rawValue)CalendarSyncMap.json"
    }

    static func load(namespace: Namespace) -> [String: String] {
        CalendarSyncMapDiskPersistence.loadMapSync(fileName: fileName(for: namespace)) ?? [:]
    }

    static func persist(namespace: Namespace, map: [String: String], legacyUserDefaultsKey: String? = nil) {
        CalendarSyncMapDiskPersistence.persistMapSync(
            map,
            fileName: fileName(for: namespace),
            legacyUserDefaultsKey: legacyUserDefaultsKey
        )
    }

    static func migrateAppleFromLegacyIfNeeded() {
        CalendarSyncMapDiskPersistence.migrateFromUserDefaultsIfNeeded(
            legacyKey: "AppleCalendarSyncMap",
            fileName: fileName(for: .apple)
        )
    }
}
