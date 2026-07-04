// AcademicCalendarDeterministicParser.swift
// Feature: Calendar
// Purpose: Regex and table-based extraction of academic calendar events without an LLM.

import Foundation
import SwiftSoup

enum AcademicCalendarDeterministicParser {
    static func parse(
        content: String,
        config: AcademicCalendarConfig,
        subCalendarURL: String?
    ) -> [AcademicCalendarParsedEvent] {
        let structured = parseStructuredHTML(content: content, config: config, subCalendarURL: subCalendarURL)
        let listEvents = parseHTMLListItems(content: content, config: config, subCalendarURL: subCalendarURL)
        let tableEvents = parseHTMLTables(content: content, config: config, subCalendarURL: subCalendarURL)
        let lineEvents = parseTextLines(content: content, config: config, subCalendarURL: subCalendarURL)
        return AcademicCalendarEventParser.mergeNearDuplicates(structured + listEvents + tableEvents + lineEvents)
    }

    private static func parseHTMLListItems(
        content: String,
        config: AcademicCalendarConfig,
        subCalendarURL: String?
    ) -> [AcademicCalendarParsedEvent] {
        guard content.contains("<"), let doc = try? SwiftSoup.parse(content) else { return [] }
        var events: [AcademicCalendarParsedEvent] = []
        var currentTerm = "unknown"
        var currentYear = Calendar.current.component(.year, from: Date())

        for element in (try? doc.select("h1,h2,h3,li").array()) ?? [] {
            let tag = element.tagName().lowercased()
            let text = (try? element.text())?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !text.isEmpty else { continue }

            if tag == "h1" || tag == "h2" || tag == "h3", let header = parseTermHeader(text) {
                currentTerm = header.term
                currentYear = header.year
                continue
            }
            guard tag == "li" else { continue }
            guard let split = splitDateAndTitle(text) else { continue }
            guard let event = makeEvent(
                title: split.title,
                dateText: split.dateText,
                term: currentTerm,
                year: currentYear,
                config: config,
                subCalendarURL: subCalendarURL
            ) else { continue }
            events.append(event)
        }
        return events
    }

    private static func parseStructuredHTML(
        content: String,
        config: AcademicCalendarConfig,
        subCalendarURL: String?
    ) -> [AcademicCalendarParsedEvent] {
        guard content.contains("<"), let doc = try? SwiftSoup.parse(content) else { return [] }
        let blocks = (try? doc.select("h1,h2,h3,table").array()) ?? []
        var events: [AcademicCalendarParsedEvent] = []
        var currentTerm = "unknown"
        var currentYear = Calendar.current.component(.year, from: Date())

        for block in blocks {
            let tag = block.tagName().lowercased()
            if tag == "h1" || tag == "h2" || tag == "h3" {
                let text = (try? block.text())?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if let header = parseTermHeader(text) {
                    currentTerm = header.term
                    currentYear = header.year
                }
                continue
            }
            events.append(
                contentsOf: parseTableElement(
                    block,
                    term: currentTerm,
                    year: currentYear,
                    config: config,
                    subCalendarURL: subCalendarURL
                )
            )
        }
        return events
    }

    private static func parseTableElement(
        _ table: Element,
        term: String,
        year: Int,
        config: AcademicCalendarConfig,
        subCalendarURL: String?
    ) -> [AcademicCalendarParsedEvent] {
        let rows = (try? table.select("tr").array()) ?? []
        var events: [AcademicCalendarParsedEvent] = []
        var currentTerm = term
        var currentYear = year
        for row in rows {
            let cells = (try? row.select("td, th").array()) ?? []
            let values = cells.compactMap { try? $0.text() }
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            guard !values.isEmpty else { continue }

            if values.count == 1, let header = parseTermHeader(values[0]) {
                currentTerm = header.term
                currentYear = header.year
                continue
            }

            guard values.count >= 2 else { continue }
            if values[0].lowercased() == "date" { continue }

            let dateText = values[0]
            let titleText = eventTitle(from: values)
            if shouldSkipCalendarRow(dateText: dateText, title: titleText) { continue }
            guard let event = makeEvent(
                title: titleText,
                dateText: dateText,
                term: currentTerm,
                year: currentYear,
                config: config,
                subCalendarURL: subCalendarURL
            ) else { continue }
            events.append(event)
        }
        return events
    }

    private static func parseHTMLTables(
        content: String,
        config: AcademicCalendarConfig,
        subCalendarURL: String?
    ) -> [AcademicCalendarParsedEvent] {
        guard content.contains("<"), let doc = try? SwiftSoup.parse(content) else { return [] }
        let rows = (try? doc.select("tr").array()) ?? []
        var events: [AcademicCalendarParsedEvent] = []
        var currentTerm = "unknown"
        var currentYear = Calendar.current.component(.year, from: Date())

        for row in rows {
            let cells = (try? row.select("td, th").array()) ?? []
            guard !cells.isEmpty else { continue }
            let values = cells.compactMap { try? $0.text() }
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            guard !values.isEmpty else { continue }

            if values.count == 1, let header = parseTermHeader(values[0]) {
                currentTerm = header.term
                currentYear = header.year
                continue
            }

            guard values.count >= 2 else { continue }
            if values[0].lowercased() == "date" { continue }
            let dateText = values[0]
            let titleText = eventTitle(from: values)
            if shouldSkipCalendarRow(dateText: dateText, title: titleText) { continue }
            guard let event = makeEvent(
                title: titleText,
                dateText: dateText,
                term: currentTerm,
                year: currentYear,
                config: config,
                subCalendarURL: subCalendarURL
            ) else { continue }
            events.append(event)
        }
        return events
    }

    private static func eventTitle(from values: [String]) -> String {
        if values.count >= 3, isWeekday(values[1]) {
            return values[2]
        }
        if values.count >= 3, looksLikeDate(values[1]) {
            return values[2...].joined(separator: " ")
        }
        return values[1...].joined(separator: " ")
    }

    private static func isWeekday(_ value: String) -> Bool {
        let lower = value.lowercased()
        return ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
            .contains(where: { lower.contains($0) })
    }

    private static func looksLikeDate(_ value: String) -> Bool {
        let lower = value.lowercased()
        return lower.range(
            of: #"\b(?:jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)"#,
            options: .regularExpression
        ) != nil || lower.range(of: #"\d{1,2}"#, options: .regularExpression) != nil
    }

    private static func parseTextLines(
        content: String,
        config: AcademicCalendarConfig,
        subCalendarURL: String?
    ) -> [AcademicCalendarParsedEvent] {
        var events: [AcademicCalendarParsedEvent] = []
        var currentTerm = "unknown"
        var currentYear = Calendar.current.component(.year, from: Date())

        for rawLine in content.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            if let header = parseTermHeader(line) {
                currentTerm = header.term
                currentYear = header.year
                continue
            }

            guard let split = splitDateAndTitle(line) else { continue }
            guard let event = makeEvent(
                title: split.title,
                dateText: split.dateText,
                term: currentTerm,
                year: currentYear,
                config: config,
                subCalendarURL: subCalendarURL
            ) else { continue }
            events.append(event)
        }
        return events
    }

    private static func splitDateAndTitle(_ line: String) -> (dateText: String, title: String)? {
        let patterns = [
            #"^(.+?\d{4})\s*[-–—:]\s*(.+)$"#,
            #"^([A-Za-z]+\.?\s+\d{1,2})\s*[-–—:]\s*(.+)$"#,
            #"^(.+?\d{1,2}(?:,?\s+\d{4})?)\s{2,}(.+)$"#,
            #"^(.+?\d{1,2})\s+(.+)$"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                  let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                  match.numberOfRanges >= 3,
                  let dateRange = Range(match.range(at: 1), in: line),
                  let titleRange = Range(match.range(at: 2), in: line) else { continue }
            let dateText = String(line[dateRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            let title = String(line[titleRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !dateText.isEmpty, !title.isEmpty else { continue }
            return (dateText, title)
        }
        return nil
    }

    static func parseTermHeader(_ line: String) -> (term: String, year: Int)? {
        let lower = line.lowercased()
        let terms = ["fall", "spring", "summer", "winter"]
        guard let term = terms.first(where: { lower.contains($0) }) else { return nil }
        let yearPattern = #"(20\d{2})"#
        guard let regex = try? NSRegularExpression(pattern: yearPattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let yearRange = Range(match.range(at: 1), in: line),
              let year = Int(line[yearRange]) else {
            return (term.capitalized, Calendar.current.component(.year, from: Date()))
        }
        return (term.capitalized, year)
    }

    private static func makeEvent(
        title: String,
        dateText: String,
        term: String,
        year: Int,
        config: AcademicCalendarConfig,
        subCalendarURL: String?
    ) -> AcademicCalendarParsedEvent? {
        let normalizedTitle = AcademicCalendarTitleNormalizer.oneLineTitle(title)
        guard !normalizedTitle.isEmpty else { return nil }
        guard normalizedTitle.count >= 4 else { return nil }
        guard !isWeekday(normalizedTitle) else { return nil }
        guard let start = parseFlexibleDate(dateText, fallbackYear: year, timeZoneID: config.timeZoneID) else { return nil }

        let eventYear = year > 0 ? year : Calendar.current.component(.year, from: start)
        let raw = AcademicCalendarEventParser.RawEvent(
            title: normalizedTitle,
            startDate: AcademicCalendarIdentityResolver.dayString(start, timeZoneID: config.timeZoneID),
            endDate: AcademicCalendarIdentityResolver.dayString(start, timeZoneID: config.timeZoneID),
            allDay: true,
            status: "confirmed",
            term: term,
            year: eventYear,
            level: config.levelScope.rawValue,
            confidence: 0.7
        )
        return AcademicCalendarEventParser.makeParsedEvent(raw, config: config, subCalendarURL: subCalendarURL)
    }

    private static func shouldSkipCalendarRow(dateText: String, title: String) -> Bool {
        if title.contains("%") { return true }
        let lowerTitle = title.lowercased()
        if lowerTitle.contains("tuition") && lowerTitle.contains("refund") { return true }
        let lowerDate = dateText.lowercased()
        if lowerDate.contains(" to ") && title.count < 12 { return true }
        return false
    }

    private static func parseFlexibleDate(_ value: String, fallbackYear: Int, timeZoneID: String) -> Date? {
        var trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        trimmed = trimmed.replacingOccurrences(of: #"^(?i)on or before\s+"#, with: "", options: .regularExpression)
        trimmed = trimmed.replacingOccurrences(of: #"^(?i)on or after\s+"#, with: "", options: .regularExpression)
        trimmed = trimmed.replacingOccurrences(of: #"^(?i)(?:mon|monday|tue|tues|tuesday|wed|wednesday|thu|thur|thurs|thursday|fri|friday|sat|saturday|sun|sunday),?\s+"#, with: "", options: .regularExpression)
        trimmed = trimmed.replacingOccurrences(of: #"\s+\d{1,2}:\d{2}\s*(?:AM|PM)\s*$"#, with: "", options: [.regularExpression, .caseInsensitive])
        trimmed = trimmed.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        trimmed = trimmed.replacingOccurrences(of: #"\s*\(.+\)\s*$"#, with: "", options: .regularExpression)
        if let range = trimmed.range(of: #"\s+to\s+"#, options: [.regularExpression, .caseInsensitive]) {
            trimmed = String(trimmed[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let parsed = AcademicCalendarEventParser.parseDay(trimmed, timeZoneID: timeZoneID) {
            return parsed
        }

        let yearPattern = #"(20\d{2})"#
        var explicitYear: Int?
        if let regex = try? NSRegularExpression(pattern: yearPattern),
           let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
           let yearRange = Range(match.range(at: 1), in: trimmed) {
            explicitYear = Int(trimmed[yearRange])
        }

        let formatter = DateFormatter()
        formatter.calendar = AcademicCalendarTimezone.calendar(for: timeZoneID)
        formatter.timeZone = TimeZone(identifier: timeZoneID)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let formats = [
            "M/d/yyyy",
            "M/d/yy",
            "MMMM d, yyyy",
            "MMMM d yyyy",
            "MMM d, yyyy",
            "MMM d yyyy",
            "MMM. d, yyyy",
            "MMM. d yyyy",
            "EEEE, MMMM d, yyyy",
            "EEEE, MMM d, yyyy",
            "EEEE, MMM. d, yyyy",
            "EEEE, MMM. d",
            "MMMM d",
            "MMM d",
            "MMM. d"
        ]
        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: trimmed) {
                if !format.contains("y"), let year = explicitYear ?? Optional(fallbackYear) {
                    return replaceYear(in: date, year: year, timeZoneID: timeZoneID)
                }
                return date
            }
        }
        return nil
    }

    private static func replaceYear(in date: Date, year: Int, timeZoneID: String) -> Date? {
        var calendar = AcademicCalendarTimezone.calendar(for: timeZoneID)
        calendar.timeZone = TimeZone(identifier: timeZoneID) ?? .current
        var components = calendar.dateComponents([.month, .day], from: date)
        components.year = year
        return calendar.date(from: components)
    }
}
