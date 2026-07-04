// CalendarEventDisplayColorResolver.swift
// Feature: Calendar
// Purpose: Calendar module — CalendarEventDisplayColorResolver.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI

/// Resolves display color for calendar events: custom hex → legacy UserDefaults → source calendar → kind default.
public enum CalendarEventDisplayColorResolver {
    public static func resolve(
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

    public static func resolve(
        for event: CalendarStoredEvent,
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

    /// Maps stored hex to Google Calendar API `colorId` (1–11) when possible.
    public static func googleColorId(fromStoredHex hex: String?) -> String? {
        guard let normalized = normalizedHex(hex) else { return nil }
        guard let id = googleEventColorHexByID.first(where: {
            $0.value.caseInsensitiveCompare(normalized) == .orderedSame
        })?.key else {
            return nil
        }
        return String(id)
    }

    /// Maps Google Calendar API `colorId` (1–11) to stored hex; passes through valid hex unchanged.
    public static func googleStoredColorHex(from colorId: String?) -> String? {
        guard let raw = colorId?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        if let id = Int(raw), let mapped = googleEventColorHexByID[id] {
            return mapped
        }
        return normalizedHex(raw)
    }

    private static let googleEventColorHexByID: [Int: String] = [
        1: "a4bdfc",
        2: "7ae7bf",
        3: "dbadff",
        4: "ff887c",
        5: "fbd75b",
        6: "ffb878",
        7: "46d6db",
        8: "e1e1e1",
        9: "5484ed",
        10: "51b749",
        11: "dc2127",
    ]

    private static func normalizedHex(_ raw: String?) -> String? {
        guard var hex = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !hex.isEmpty else {
            return nil
        }
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6 else { return nil }
        return hex
    }
}
