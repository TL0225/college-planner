// CalendarEventDisplayColorResolver.swift
// Feature: Calendar
// Purpose: Calendar module — CalendarEventDisplayColorResolver.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI

/// Resolves display color for calendar events: custom hex → legacy UserDefaults → source calendar → kind default.
enum CalendarEventDisplayColorResolver {
    static func resolve(
        customColorHex: String?,
        legacyEventID: UUID?,
        sourceCalendarColor: Color?,
        kindDefault: Color
    ) -> Color {
        if let hex = normalizedHex(customColorHex) {
            return Color(hex: hex)
        }
        if let legacyEventID, let legacy = EventColorOverrides.storedHex(for: legacyEventID) {
            return Color(hex: legacy)
        }
        if let sourceCalendarColor {
            return sourceCalendarColor
        }
        return kindDefault
    }

    static func resolve(
        for event: CalendarEvent,
        sourceCalendarColor: Color?,
        kindDefault: Color
    ) -> Color {
        resolve(
            customColorHex: event.customColorHex,
            legacyEventID: event.id,
            sourceCalendarColor: sourceCalendarColor,
            kindDefault: kindDefault
        )
    }

    private static func normalizedHex(_ raw: String?) -> String? {
        guard var hex = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !hex.isEmpty else {
            return nil
        }
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6 else { return nil }
        return hex
    }
}
