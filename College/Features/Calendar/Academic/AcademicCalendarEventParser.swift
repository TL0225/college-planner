// AcademicCalendarEventParser.swift
// Feature: Calendar
// Purpose: Deterministic parsing and normalization of extracted academic calendar events.

import CollegeCalendar
import Foundation

enum AcademicCalendarEventParser {
    struct RawEvent: Decodable {
        var title: String
        var startDate: String
        var endDate: String
        var allDay: Bool?
        var status: String?
        var term: String?
        var year: Int?
        var level: String?
        var confidence: Double?
    }

    static func parseJSONArray(
        _ rawJSON: String,
        config: AcademicCalendarConfig,
        subCalendarURL: String?
    ) -> [AcademicCalendarParsedEvent] {
        guard let payload = JSONSanitizer.extractJSONPayload(from: rawJSON),
              let data = payload.data(using: .utf8) else { return [] }

        let decoder = JSONDecoder()
        let rawEvents: [RawEvent]
        if let array = try? decoder.decode([RawEvent].self, from: data) {
            rawEvents = array
        } else if let wrapped = try? decoder.decode([String: [RawEvent]].self, from: data),
                  let events = wrapped["events"] ?? wrapped.values.first {
            rawEvents = events
        } else {
            return []
        }

        var parsed: [AcademicCalendarParsedEvent] = []
        for raw in rawEvents {
            guard let event = makeParsedEvent(raw, config: config, subCalendarURL: subCalendarURL) else { continue }
            parsed.append(event)
        }
        return mergeNearDuplicates(parsed)
    }

    static func makeParsedEvent(
        _ raw: RawEvent,
        config: AcademicCalendarConfig,
        subCalendarURL: String?
    ) -> AcademicCalendarParsedEvent? {
        let title = AcademicCalendarTitleNormalizer.oneLineTitle(raw.title)
        guard !title.isEmpty else { return nil }

        guard let start = parseDay(raw.startDate, timeZoneID: config.timeZoneID),
              let end = parseDay(raw.endDate, timeZoneID: config.timeZoneID) else { return nil }

        let status = AcademicCalendarEventStatus(rawValue: (raw.status ?? "confirmed").lowercased()) ?? .confirmed
        let term = (raw.term ?? "unknown").trimmingCharacters(in: .whitespacesAndNewlines)
        let year = raw.year ?? Calendar.current.component(.year, from: start)
        let level = AcademicCalendarLevelScope(rawValue: (raw.level ?? config.levelScope.rawValue).lowercased()) ?? config.levelScope

        let scopeKey = AcademicCalendarIdentityResolver.makeScopeKey(
            term: term,
            year: year,
            level: level,
            subCalendarURL: subCalendarURL
        )
        let startDay = AcademicCalendarIdentityResolver.dayString(start, timeZoneID: config.timeZoneID)
        let identityKey = AcademicCalendarIdentityResolver.scrapedIdentityKey(
            schoolID: config.schoolID,
            scopeKey: scopeKey,
            title: title,
            startDay: startDay
        )
        let signature = AcademicCalendarTitleNormalizer.identitySignature(title: title, startDay: startDay)

        var confidence = raw.confidence ?? 0.75
        let risky = title.contains(",") || raw.startDate.contains("-") && raw.startDate.filter({ $0 == "-" }).count > 2
        if risky { confidence = min(confidence, 0.55) }

        let allDayStart = AcademicCalendarTimezone.allDayStart(of: start, timeZoneID: config.timeZoneID)
        let allDayEnd = AcademicCalendarTimezone.allDayEndExclusive(endDay: end, timeZoneID: config.timeZoneID)

        return AcademicCalendarParsedEvent(
            id: identityKey,
            title: status == .tentative ? "\(title) (tentative)" : title,
            startDate: allDayStart,
            endDate: allDayEnd,
            allDay: raw.allDay ?? true,
            status: status,
            term: term,
            year: year,
            level: level,
            confidence: confidence,
            scopeKey: scopeKey,
            identityKey: identityKey,
            identitySignature: signature,
            providerEventId: nil,
            notes: nil,
            isLowConfidence: confidence < 0.6
        )
    }

    static func parseDay(_ value: String, timeZoneID: String) -> Date? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let formatter = DateFormatter()
        formatter.calendar = AcademicCalendarTimezone.calendar(for: timeZoneID)
        formatter.timeZone = TimeZone(identifier: timeZoneID)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in ["yyyy-MM-dd", "yyyy/MM/dd", "MM/dd/yyyy"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: trimmed) { return date }
        }
        return nil
    }

    static func mergeNearDuplicates(_ events: [AcademicCalendarParsedEvent]) -> [AcademicCalendarParsedEvent] {
        var result: [AcademicCalendarParsedEvent] = []
        for event in events {
            if let idx = result.firstIndex(where: {
                $0.scopeKey == event.scopeKey
                    && AcademicCalendarIdentityResolver.dayString($0.startDate, timeZoneID: TimeZone.current.identifier) == AcademicCalendarIdentityResolver.dayString(event.startDate, timeZoneID: TimeZone.current.identifier)
                    && AcademicCalendarTitleNormalizer.areNearDuplicates($0.title, event.title)
            }) {
                if event.confidence > result[idx].confidence {
                    result[idx] = event
                }
            } else {
                result.append(event)
            }
        }
        return result
    }

    static func filterByImportedScopes(
        _ events: [AcademicCalendarParsedEvent],
        scopes: [AcademicCalendarImportedScope]
    ) -> [AcademicCalendarParsedEvent] {
        guard !scopes.isEmpty else { return events }
        return events.filter { event in
            scopes.contains { scope in
                scope.term.caseInsensitiveCompare(event.term) == .orderedSame
                    && scope.year == event.year
                    && (scope.level == .all || scope.level == event.level || event.level == .all)
            }
        }
    }

    static func fromICS(
        events: [ICSCalendarParser.ParsedEvent],
        config: AcademicCalendarConfig,
        subCalendarURL: String?
    ) -> [AcademicCalendarParsedEvent] {
        events.compactMap { parsed in
            let title = AcademicCalendarTitleNormalizer.oneLineTitle(parsed.title)
            guard !title.isEmpty else { return nil }
            let term = "ics"
            let year = Calendar.current.component(.year, from: parsed.start)
            let scopeKey = AcademicCalendarIdentityResolver.makeScopeKey(term: term, year: year, level: .all, subCalendarURL: subCalendarURL)
            let startDay = AcademicCalendarIdentityResolver.dayString(parsed.start, timeZoneID: config.timeZoneID)
            let identityKey = AcademicCalendarIdentityResolver.icsIdentityKey(uid: parsed.uid)
            let signature = AcademicCalendarTitleNormalizer.identitySignature(title: title, startDay: startDay)
            return AcademicCalendarParsedEvent(
                id: identityKey,
                title: title,
                startDate: parsed.start,
                endDate: parsed.end,
                allDay: parsed.allDay,
                status: .confirmed,
                term: term,
                year: year,
                level: .all,
                confidence: 0.95,
                scopeKey: scopeKey,
                identityKey: identityKey,
                identitySignature: signature,
                providerEventId: parsed.uid,
                notes: parsed.notes,
                isLowConfidence: false
            )
        }
    }
}
