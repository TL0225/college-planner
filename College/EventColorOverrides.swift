import SwiftUI

/// Stores per-event color overrides in UserDefaults.
///
/// This avoids needing a Core Data migration just to support custom colors.
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
}
