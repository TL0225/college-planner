// CalendarOverlapPolicy.swift
// Feature: Calendar
// Purpose: Overlap handling policy for calendar event save.

import Foundation

public enum CalendarOverlapPolicy: String, CaseIterable, Sendable, Identifiable {
    case warn
    case block

    public var id: String { rawValue }

    public static let storageKey = "calendar.overlapPolicy"
    private static let legacyBlockKey = "calendar.blockSaveOnOverlap"

    public var blocksSave: Bool { self == .block }

    public var label: String {
        switch self {
        case .warn: return "Warn only"
        case .block: return "Block save"
        }
    }

    public var description: String {
        switch self {
        case .warn:
            return "Overlapping events show a warning but can still be saved."
        case .block:
            return "Save & Sync is blocked when this event overlaps another."
        }
    }

    public static func resolved(selection: String?) -> CalendarOverlapPolicy {
        if let selection, let policy = CalendarOverlapPolicy(rawValue: selection) {
            return policy
        }
        if UserDefaults.standard.bool(forKey: legacyBlockKey) {
            return .block
        }
        return .warn
    }
}
