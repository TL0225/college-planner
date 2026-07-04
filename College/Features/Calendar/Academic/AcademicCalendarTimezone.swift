// AcademicCalendarTimezone.swift
// Feature: Calendar
// Purpose: Resolve school time zones from manifest or US state codes.

import Foundation

enum AcademicCalendarTimezone {
    private static let stateToTimeZone: [String: String] = [
        "AL": "America/Chicago", "AK": "America/Anchorage", "AZ": "America/Phoenix",
        "AR": "America/Chicago", "CA": "America/Los_Angeles", "CO": "America/Denver",
        "CT": "America/New_York", "DE": "America/New_York", "DC": "America/New_York",
        "FL": "America/New_York", "GA": "America/New_York", "HI": "Pacific/Honolulu",
        "ID": "America/Boise", "IL": "America/Chicago", "IN": "America/Indiana/Indianapolis",
        "IA": "America/Chicago", "KS": "America/Chicago", "KY": "America/New_York",
        "LA": "America/Chicago", "ME": "America/New_York", "MD": "America/New_York",
        "MA": "America/New_York", "MI": "America/Detroit", "MN": "America/Chicago",
        "MS": "America/Chicago", "MO": "America/Chicago", "MT": "America/Denver",
        "NE": "America/Chicago", "NV": "America/Los_Angeles", "NH": "America/New_York",
        "NJ": "America/New_York", "NM": "America/Denver", "NY": "America/New_York",
        "NC": "America/New_York", "ND": "America/Chicago", "OH": "America/New_York",
        "OK": "America/Chicago", "OR": "America/Los_Angeles", "PA": "America/New_York",
        "RI": "America/New_York", "SC": "America/New_York", "SD": "America/Chicago",
        "TN": "America/Chicago", "TX": "America/Chicago", "UT": "America/Denver",
        "VT": "America/New_York", "VA": "America/New_York", "WA": "America/Los_Angeles",
        "WV": "America/New_York", "WI": "America/Chicago", "WY": "America/Denver"
    ]

    static func resolve(manifest: SchoolManifest?) -> String {
        if let tz = manifest?.timeZoneID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !tz.isEmpty,
           TimeZone(identifier: tz) != nil {
            return tz
        }
        if let state = manifest?.stateCode?.uppercased(),
           let tz = stateToTimeZone[state] {
            return tz
        }
        return TimeZone.current.identifier
    }

    static func calendar(for timeZoneID: String) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: timeZoneID) ?? .current
        return cal
    }

    static func allDayStart(of day: Date, timeZoneID: String) -> Date {
        let cal = calendar(for: timeZoneID)
        return cal.startOfDay(for: day)
    }

    /// End-exclusive all-day boundary (start of day after end date).
    static func allDayEndExclusive(endDay: Date, timeZoneID: String) -> Date {
        let cal = calendar(for: timeZoneID)
        let start = cal.startOfDay(for: endDay)
        return cal.date(byAdding: .day, value: 1, to: start) ?? start
    }
}
