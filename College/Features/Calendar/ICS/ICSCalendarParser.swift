// ICSCalendarParser.swift
// Feature: Calendar
// Purpose: Calendar module — ParsedEvent.
// Data: CollegePersistence / repositories when applicable.

import Foundation

/// Minimal ICS parser for subscription import (Phase 4). Expands to Rust/UniFFI per CALENDAR_FFI.md.
enum ICSCalendarParser {
    struct ParsedEvent: Sendable {
        var uid: String
        var title: String
        var start: Date
        var end: Date
        var allDay: Bool
        var location: String?
        var notes: String?
    }

    static func parse(data: Data) throws -> [ParsedEvent] {
        guard let text = String(data: data, encoding: .utf8) else {
            throw ICSParseError.invalidEncoding
        }
        return parse(icsText: text)
    }

    static func parse(icsText: String) -> [ParsedEvent] {
        var events: [ParsedEvent] = []
        var inEvent = false
        var buffer: [String: String] = [:]

        for rawLine in icsText.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line == "BEGIN:VEVENT" {
                inEvent = true
                buffer = [:]
                continue
            }
            if line == "END:VEVENT" {
                if let event = eventFrom(buffer: buffer) {
                    events.append(event)
                }
                inEvent = false
                buffer = [:]
                continue
            }
            guard inEvent, let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<colon]).components(separatedBy: ";").first ?? ""
            let value = String(line[line.index(after: colon)...])
            buffer[key] = value
        }
        return events
    }

    private static func eventFrom(buffer: [String: String]) -> ParsedEvent? {
        guard let uid = buffer["UID"],
              let summary = buffer["SUMMARY"],
              let startRaw = buffer["DTSTART"],
              let start = parseICSDate(startRaw)
        else { return nil }

        let end: Date
        if let endRaw = buffer["DTEND"], let parsedEnd = parseICSDate(endRaw) {
            end = parsedEnd
        } else {
            end = start.addingTimeInterval(3600)
        }

        let allDay = startRaw.count == 8 || startRaw.hasPrefix("VALUE=DATE")
        return ParsedEvent(
            uid: uid,
            title: summary,
            start: start,
            end: end,
            allDay: allDay,
            location: buffer["LOCATION"],
            notes: buffer["DESCRIPTION"]
        )
    }

    private static func parseICSDate(_ raw: String) -> Date? {
        let cleaned = raw.replacingOccurrences(of: "Z", with: "")
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        if cleaned.count == 8 {
            formatter.dateFormat = "yyyyMMdd"
            return formatter.date(from: cleaned)
        }
        formatter.dateFormat = "yyyyMMdd'T'HHmmss"
        return formatter.date(from: cleaned)
    }
}

enum ICSParseError: Error {
    case invalidEncoding
}
