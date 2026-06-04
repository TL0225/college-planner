// CalendarRecurrenceExpander.swift
// Feature: Calendar
// Purpose: Calendar module — Occurrence.
// Data: CollegePersistence / repositories when applicable.

import EventKit
import Foundation

/// Recurrence expansion (Phase 2d Option B): EventKit for Apple-linked events; local RRULE parsing fallback.
enum CalendarRecurrenceExpander {
    struct Occurrence: Sendable {
        var start: Date
        var end: Date
    }

    /// Expands occurrences in `window` for a stored recurrence rule string.
    static func expand(
        rule: String?,
        start: Date,
        end: Date,
        windowStart: Date,
        windowEnd: Date
    ) -> [Occurrence] {
        guard let rule, !rule.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            guard start < windowEnd, end > windowStart else { return [] }
            return [Occurrence(start: start, end: end)]
        }

        if rule.hasPrefix("FREQ=") || rule.contains("RRULE:") {
            return expandRRULE(rule: rule, dtStart: start, duration: end.timeIntervalSince(start), windowStart: windowStart, windowEnd: windowEnd)
        }

        return expandJSONPayload(rule: rule, fallbackStart: start, fallbackEnd: end, windowStart: windowStart, windowEnd: windowEnd)
    }

    /// EventKit expansion when an `EKEvent` is available (Apple sync path).
    static func expand(ekEvent: EKEvent, in store: EKEventStore, windowStart: Date, windowEnd: Date) -> [Occurrence] {
        guard let calendar = ekEvent.calendar else { return [] }
        let predicate = store.predicateForEvents(withStart: windowStart, end: windowEnd, calendars: [calendar])
        let matches = store.events(matching: predicate).filter { $0.eventIdentifier == ekEvent.eventIdentifier }
        return matches.compactMap { ev in
            guard let s = ev.startDate, let e = ev.endDate else { return nil }
            return Occurrence(start: s, end: e)
        }
    }

    // MARK: - Private

    private static func expandRRULE(
        rule: String,
        dtStart: Date,
        duration: TimeInterval,
        windowStart: Date,
        windowEnd: Date
    ) -> [Occurrence] {
        let normalized = rule.replacingOccurrences(of: "RRULE:", with: "")
        var freq = "WEEKLY"
        var interval = 1
        for part in normalized.split(separator: ";") {
            let kv = part.split(separator: "=", maxSplits: 1).map(String.init)
            guard kv.count == 2 else { continue }
            switch kv[0].uppercased() {
            case "FREQ": freq = kv[1].uppercased()
            case "INTERVAL": interval = max(1, Int(kv[1]) ?? 1)
            default: break
            }
        }

        var results: [Occurrence] = []
        var cursor = dtStart
        let step: TimeInterval
        switch freq {
        case "DAILY": step = 86400 * Double(interval)
        case "MONTHLY": step = 86400 * 30 * Double(interval)
        default: step = 86400 * 7 * Double(interval)
        }

        while cursor < windowEnd {
            let occEnd = cursor.addingTimeInterval(duration)
            if cursor >= windowStart {
                results.append(Occurrence(start: cursor, end: occEnd))
            }
            cursor = cursor.addingTimeInterval(step)
            if results.count > 500 { break }
        }
        return results
    }

    private static func expandJSONPayload(
        rule: String,
        fallbackStart: Date,
        fallbackEnd: Date,
        windowStart: Date,
        windowEnd: Date
    ) -> [Occurrence] {
        guard let data = rule.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let freq = (json["frequency"] as? String)?.lowercased()
        else {
            guard fallbackStart < windowEnd, fallbackEnd > windowStart else { return [] }
            return [Occurrence(start: fallbackStart, end: fallbackEnd)]
        }

        let interval = max(1, json["interval"] as? Int ?? 1)
        var cursor = fallbackStart
        let duration = fallbackEnd.timeIntervalSince(fallbackStart)
        var results: [Occurrence] = []
        let step: TimeInterval
        switch freq {
        case "daily": step = 86400 * Double(interval)
        case "monthly": step = 86400 * 30 * Double(interval)
        default: step = 86400 * 7 * Double(interval)
        }

        while cursor < windowEnd {
            let end = cursor.addingTimeInterval(duration)
            if cursor >= windowStart { results.append(Occurrence(start: cursor, end: end)) }
            cursor = cursor.addingTimeInterval(step)
            if results.count > 500 { break }
        }
        return results
    }
}
