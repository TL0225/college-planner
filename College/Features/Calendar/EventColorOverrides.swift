// EventColorOverrides.swift
// Feature: Calendar
// Purpose: Calendar module — EventColorOverrides.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI

/// Stores per-event color overrides in UserDefaults.
///
/// This avoids needing a local store migration just to support custom colors.
enum EventColorOverrides {
    private static let keyPrefix = "College.EventColorOverride."

    private static func key(for eventID: UUID) -> String {
        keyPrefix + eventID.uuidString
    }

    static func color(for eventID: UUID) -> Color? {
        let key = key(for: eventID)
        guard let hex = UserDefaults.standard.string(forKey: key) else { return nil }
        return Color(hex: hex)
    }

    static func setColor(_ color: Color, for eventID: UUID) {
        guard let hex = color.hexRGBString() else { return }
        let key = key(for: eventID)
        UserDefaults.standard.set(hex, forKey: key)
    }

    static func clearColor(for eventID: UUID) {
        let key = key(for: eventID)
        UserDefaults.standard.removeObject(forKey: key)
    }

    static func storedHex(for eventID: UUID) -> String? {
        UserDefaults.standard.string(forKey: key(for: eventID))
    }

    static func allStoredOverrides() -> [(UUID, String)] {
        let prefix = keyPrefix
        return UserDefaults.standard.dictionaryRepresentation().compactMap { entry in
            guard entry.key.hasPrefix(prefix), let uuid = UUID(uuidString: String(entry.key.dropFirst(prefix.count)))
            else { return nil }
            return (uuid, entry.value as? String ?? "")
        }
    }
}
