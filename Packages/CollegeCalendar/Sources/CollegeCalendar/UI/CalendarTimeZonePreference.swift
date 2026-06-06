// CalendarTimeZonePreference.swift
// Feature: Calendar
// Purpose: Calendar module — Option.
// Data: CollegePersistence / repositories when applicable.

import Foundation

public enum CalendarTimeZonePreference {
    public static let storageKey = "calendarTimeZoneSelection"
    public static let systemValue = "__system__"

    public static func resolvedTimeZone(selection: String) -> TimeZone {
        if selection == systemValue {
            return .autoupdatingCurrent
        }
        return TimeZone(identifier: selection) ?? .autoupdatingCurrent
    }

    public static func displayTitle(for timeZone: TimeZone, locale: Locale = .autoupdatingCurrent) -> String {
        // Prefer a friendly localized name, fall back to identifier.
        if let name = timeZone.localizedName(for: .standard, locale: locale), !name.isEmpty {
            return name
        }
        return timeZone.identifier
    }

    static func displaySubtitle(for timeZone: TimeZone) -> String {
        // Identifier is always stable and searchable.
        timeZone.identifier
    }

    static func gmtOffsetStamp(_ date: Date, timeZone: TimeZone) -> String {
        let seconds = timeZone.secondsFromGMT(for: date)
        let sign = seconds >= 0 ? "+" : "-"
        let absSeconds = abs(seconds)
        let hours = absSeconds / 3600
        let minutes = (absSeconds % 3600) / 60
        if minutes == 0 {
            return String(format: "GMT%@%02d", sign, hours)
        }
        return String(format: "GMT%@%02d:%02d", sign, hours, minutes)
    }

    public struct Option: Identifiable, Sendable {
        public let id: String
        public let title: String
        public let subtitle: String
    }

    public static func allOptions(locale: Locale = .autoupdatingCurrent) -> [Option] {
        let tzs: [Option] = TimeZone.knownTimeZoneIdentifiers.compactMap { id in
            guard let tz = TimeZone(identifier: id) else { return nil }
            // Prefer a short city-ish title for menus (grouped by region elsewhere).
            let title: String = {
                let parts = id.split(separator: "/")
                if let last = parts.last {
                    return String(last).replacingOccurrences(of: "_", with: " ")
                }
                return displayTitle(for: tz, locale: locale)
            }()
            return Option(id: id, title: title, subtitle: gmtOffsetStamp(Date(), timeZone: tz))
        }

        return tzs.sorted {
            let a = $0.title.localizedCaseInsensitiveCompare($1.title)
            if a != .orderedSame { return a == .orderedAscending }
            return $0.subtitle.localizedCaseInsensitiveCompare($1.subtitle) == .orderedAscending
        }
    }

    public struct Group: Identifiable, Sendable {
        public let id: String
        public let region: String
        public let options: [Option]
    }

    public static func groupedOptions(locale: Locale = .autoupdatingCurrent) -> [Group] {
        let options = allOptions(locale: locale)
        let grouped = Dictionary(grouping: options) { opt -> String in
            opt.id.split(separator: "/").first.map(String.init) ?? "Other"
        }

        let regions = grouped.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        return regions.map { region in
            let opts = (grouped[region] ?? []).sorted { a, b in
                let cmp = a.title.localizedCaseInsensitiveCompare(b.title)
                if cmp != .orderedSame { return cmp == .orderedAscending }
                return a.id.localizedCaseInsensitiveCompare(b.id) == .orderedAscending
            }
            return Group(id: region, region: region, options: opts)
        }
    }
}

