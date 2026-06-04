// NaturalLanguageEventParser.swift
// Feature: Core
// Purpose: Core module — ParsedCalendarIntent.
// Data: CollegePersistence / repositories when applicable.

import Foundation

struct ParsedCalendarIntent: Sendable {
    var title: String
    var start: Date?
    var end: Date?
    var allDay: Bool
}

/// Phase 7: regex-first NL parser (off main actor via `@concurrent`).
enum NaturalLanguageEventParser {
    @concurrent
    static func parse(_ input: String, referenceDate: Date = Date()) async throws -> ParsedCalendarIntent {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ParsedCalendarIntent(title: "Event", start: nil, end: nil, allDay: false)
        }

        var title = trimmed
        var start: Date?
        var end: Date?
        var allDay = false

        let lower = trimmed.lowercased()
        if lower.contains("tomorrow") {
            let cal = Calendar.current
            let day = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: referenceDate)) ?? referenceDate
            start = cal.date(bySettingHour: 12, minute: 0, second: 0, of: day)
            title = title.replacingOccurrences(of: "tomorrow", with: "", options: .caseInsensitive)
        }

        if let match = trimmed.range(of: #"\b(\d{1,2})(?::(\d{2}))?\s*(am|pm)\b"#, options: .regularExpression) {
            let token = String(trimmed[match])
            if let parsed = parseTimeToken(token, on: start ?? referenceDate) {
                start = parsed
                title = title.replacingOccurrences(of: token, with: "", options: .caseInsensitive)
            }
        }

        if lower.contains("all day") || lower.contains("all-day") {
            allDay = true
            title = title.replacingOccurrences(of: "all day", with: "", options: .caseInsensitive)
            title = title.replacingOccurrences(of: "all-day", with: "", options: .caseInsensitive)
        }

        if let start {
            end = start.addingTimeInterval(3600)
        }

        title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty { title = "Event" }

        return ParsedCalendarIntent(title: title, start: start, end: end, allDay: allDay)
    }

    private static func parseTimeToken(_ token: String, on day: Date) -> Date? {
        let parts = token.lowercased().split(separator: " ")
        guard parts.count >= 2 else { return nil }
        let timePart = parts[0]
        let ampm = parts[1]
        let hm = timePart.split(separator: ":")
        guard let hourRaw = Int(hm[0]) else { return nil }
        let minute = hm.count > 1 ? (Int(hm[1]) ?? 0) : 0
        var hour = hourRaw % 12
        if ampm == "pm" { hour += 12 }
        return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: day)
    }
}
