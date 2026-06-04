// SyllabusScheduleInference.swift
// Feature: SyllabusAI
// Purpose: SyllabusAI module — Extraction.
// Data: CollegePersistence / repositories when applicable.

import Foundation

enum SyllabusScheduleExtractor {
    private static let dateDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)

    // Regex: section/lecture/rec/lab label, e.g. "Section A:", "Lec 01", "REC B:"
    private static let sectionLabelRegex = try? NSRegularExpression(
        pattern: #"(?i)\b(section|sec|lecture|lec|recitation|rec|discussion|dis|lab)\s*([A-Z0-9]+)?\s*[:\-–]?\s*"#,
        options: []
    )

    struct Extraction: Sendable {
        let schedule: SyllabusCourseSchedule?
        let sections: [SyllabusSection]
        let warnings: [String]
    }

    /// Best-effort extraction of course date range + meeting pattern from raw syllabus text.
    /// Also detects multiple sections when present.
    static func extract(from text: String, defaultYear: Int?) -> Extraction {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var warnings: [String] = []

        // --- Multi-section detection ---
        let sections = extractSections(from: lines)

        // 1) Look for a line that likely contains the course meeting pattern.
        var meetingDays: [SyllabusWeekday] = []
        var startTime: String?
        var endTime: String?

        // If sections were detected, use the first section's info as the primary schedule.
        if let first = sections.first {
            meetingDays = first.meetingDays ?? []
            startTime = first.startTime
            endTime = first.endTime
        } else {
            for line in lines {
                if meetingDays.isEmpty {
                    let days = SyllabusScheduleParsing.parseWeekdays(from: line)
                    if !days.isEmpty {
                        meetingDays = days
                    }
                }

                if startTime == nil || endTime == nil {
                    if let (s, e) = SyllabusScheduleParsing.parseTimeRange(from: line) {
                        startTime = s
                        endTime = e
                    }
                }

                if !meetingDays.isEmpty, startTime != nil || endTime != nil {
                    break
                }
            }
        }

        // 2) Look for a line containing a term date range.
        // Prefer lines that contain two dates.
        var startDateISO: String?
        var endDateISO: String?

        let detector = Self.dateDetector
        if let detector {
            for line in lines {
                // Heuristic: only consider lines that imply a range.
                let lower = line.lowercased()
                let looksLikeRange = lower.contains("to") || lower.contains("through") || lower.contains("until") || lower.contains("-") || lower.contains("–") || lower.contains("—")
                let likelyContext = lower.contains("semester") || lower.contains("term") || lower.contains("course") || lower.contains("class") || lower.contains("dates") || lower.contains("runs") || lower.contains("meets") || lower.contains("from")
                guard looksLikeRange || likelyContext else { continue }

                let ns = line as NSString
                let matches = detector.matches(in: line, options: [], range: NSRange(location: 0, length: ns.length))
                if matches.count >= 2 {
                    let dates = matches.compactMap { $0.date }
                    if let minD = dates.min(), let maxD = dates.max(), minD != maxD {
                        startDateISO = SyllabusScheduleParsing.isoDate(minD)
                        endDateISO = SyllabusScheduleParsing.isoDate(maxD)
                        break
                    }
                }
            }

            // If still missing, fall back to first/last detected date in the document.
            if startDateISO == nil || endDateISO == nil {
                let ns = text as NSString
                let matches = detector.matches(in: text, options: [], range: NSRange(location: 0, length: ns.length))
                let allDates = matches.compactMap { $0.date }
                if startDateISO == nil, let first = allDates.min() {
                    startDateISO = SyllabusScheduleParsing.isoDate(first)
                }
                if endDateISO == nil, let last = allDates.max() {
                    endDateISO = SyllabusScheduleParsing.isoDate(last)
                }
            }
        } else {
            warnings.append("Date detector unavailable for schedule extraction.")
        }

        // If the schedule dates are missing a year in the source text, we rely on detector.
        // If the detected year seems wrong (e.g., current year) but semesterText suggests another,
        // we can at least warn.
        if let defaultYear, let startDateISO {
            if let y = Int(startDateISO.prefix(4)), y != defaultYear {
                // Do not override automatically; just warn.
                warnings.append("Detected course start year (\(y)) differs from inferred year (\(defaultYear)).")
            }
        }

        let schedule = SyllabusCourseSchedule(
            startDate: startDateISO,
            endDate: endDateISO,
            meetingDays: meetingDays.isEmpty ? nil : meetingDays,
            startTime: startTime,
            endTime: endTime,
            timeZone: nil
        )

        // Only return schedule if it has at least a start date and some meeting signal.
        let hasDateRange = (schedule.startDate?.isEmpty == false) && (schedule.endDate?.isEmpty == false)
        let hasMeetingSignal = (schedule.meetingDays?.isEmpty == false) || (schedule.startTime?.isEmpty == false) || (schedule.endTime?.isEmpty == false)
        if !hasDateRange && !hasMeetingSignal {
            return .init(schedule: nil, sections: sections, warnings: warnings)
        }

        return .init(schedule: schedule, sections: sections, warnings: warnings)
    }

    // MARK: - Multi-section detection

    /// Scans `lines` for section/lecture/recitation labels followed by a meeting pattern.
    /// Returns a non-empty array only when 2+ distinct sections are detected.
    private static func extractSections(from lines: [String]) -> [SyllabusSection] {
        guard let labelRegex = sectionLabelRegex else { return [] }

        var results: [SyllabusSection] = []
        var seenIDs: Set<String> = []

        for (i, line) in lines.enumerated() {
            let nsLine = line as NSString
            let range = NSRange(location: 0, length: nsLine.length)

            guard let match = labelRegex.firstMatch(in: line, options: [], range: range) else { continue }

            // Extract the kind word (section/lec/rec/lab) and the identifier letter/number.
            let kindRange = Range(match.range(at: 1), in: line)
            let idRange   = Range(match.range(at: 2), in: line)

            let kindWord = kindRange.map { String(line[$0]).lowercased() } ?? "section"
            let rawID    = idRange.map { String(line[$0]).uppercased() } ?? ""

            // Derive a display label.
            let kindLabel: String
            if kindWord.hasPrefix("lec") { kindLabel = "Lecture" }
            else if kindWord.hasPrefix("rec") { kindLabel = "Recitation" }
            else if kindWord.hasPrefix("dis") { kindLabel = "Discussion" }
            else if kindWord.hasPrefix("lab") { kindLabel = "Lab" }
            else { kindLabel = "Section" }

            let sectionID = rawID.isEmpty ? kindLabel.prefix(3).uppercased() : rawID
            let label = rawID.isEmpty ? kindLabel : "\(kindLabel) \(rawID)"

            // Skip if we've already seen this id.
            guard !seenIDs.contains(String(sectionID)) else { continue }

            // Try to parse meeting pattern from the same line and, if absent, the next line.
            let searchLines = [line] + (i + 1 < lines.count ? [lines[i + 1]] : [])
            var days: [SyllabusWeekday] = []
            var sStart: String?
            var sEnd: String?
            var location: String?

            for sl in searchLines {
                if days.isEmpty { days = SyllabusScheduleParsing.parseWeekdays(from: sl) }
                if sStart == nil, let (s, e) = SyllabusScheduleParsing.parseTimeRange(from: sl) {
                    sStart = s; sEnd = e
                }
                // Rough location: trailing word(s) after the time range (e.g. "Norton 112").
                if location == nil, sStart != nil {
                    location = extractLocation(from: sl)
                }
                if !days.isEmpty, sStart != nil { break }
            }

            // Only add if we found a meeting pattern.
            // Bare kind-words with no explicit identifier (e.g. "Lecture" or "Recitation" alone)
            // must have BOTH days AND a time range to be considered a real section — otherwise
            // they're just headings and produce false positives.
            if rawID.isEmpty {
                guard !days.isEmpty && sStart != nil else { continue }
            } else {
                guard !days.isEmpty || sStart != nil else { continue }
            }

            seenIDs.insert(String(sectionID))
            results.append(SyllabusSection(
                id: String(sectionID),
                label: label,
                meetingDays: days.isEmpty ? nil : days,
                startTime: sStart,
                endTime: sEnd,
                location: location
            ))
        }

        // Only surface sections when there are 2+; a single match is just the main schedule.
        return results.count >= 2 ? results : []
    }

    /// Extracts a trailing "Building Room" token from a schedule line, e.g.
    /// "MWF 10:00–10:50 AM Norton 112" → "Norton 112".
    private static func extractLocation(from line: String) -> String? {
        // Remove known schedule tokens to find what's left.
        var s = line
        // Strip time ranges like "10:00 AM – 10:50 AM" or "14:00-15:20"
        let timePattern = #"\d{1,2}(?::\d{2})?\s*(?:am|pm)?\s*(?:-|–|—|to)\s*\d{1,2}(?::\d{2})?\s*(?:am|pm)?"#
        if let r = s.range(of: timePattern, options: [.regularExpression, .caseInsensitive]) {
            s = String(s[r.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // Strip leading day tokens
        s = s.replacingOccurrences(of: #"(?i)\b(?:MWF|MWTh|TTh|T/Th|Mon\w*|Tue\w*|Wed\w*|Thu\w*|Fri\w*|M|W|F|T|Th)\b"#,
                                   with: "", options: .regularExpression)
              .trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip any remaining punctuation/colons from the front.
        while let first = s.first, !first.isLetter {
            s = String(s.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard s.count >= 3 else { return nil }
        return s
    }
}

enum SyllabusEventDateAutofiller {
    struct Result: Sendable {
        let events: [SyllabusEvent]
        let warnings: [String]
    }

    /// Fills missing `event.date` using a course schedule when possible.
    ///
    /// Supported inference sources (best-effort):
    /// - `event.week` + optional `event.weekday`
    /// - `event.meetingNumber`
    /// - "Week N" / "Wk N" extracted from `title`/`notes`
    /// - "Lecture N" extracted from `title`/`notes`
    static func autofillDates(
        events: [SyllabusEvent],
        schedule: SyllabusCourseSchedule,
        calendar: Calendar,
        timeZone: TimeZone
    ) -> Result {
        var warnings: [String] = []

        guard
            let startISO = schedule.startDate,
            let endISO = schedule.endDate,
            let startDate = SyllabusScheduleParsing.parseISODate(startISO, calendar: calendar, timeZone: timeZone),
            let endDate = SyllabusScheduleParsing.parseISODate(endISO, calendar: calendar, timeZone: timeZone)
        else {
            return .init(events: events, warnings: ["Could not infer missing dates because schedule start/end dates were unavailable."])
        }

        let meetingDaysSet = Set(schedule.meetingDays ?? [])
        let meetingDates = SyllabusScheduleParsing.generateMeetingDates(
            startDate: startDate,
            endDate: endDate,
            meetingDays: meetingDaysSet,
            calendar: calendar,
            timeZone: timeZone
        )

        if meetingDates.isEmpty {
            return .init(events: events, warnings: ["Could not infer missing dates because no meeting dates could be generated from the schedule."])
        }

        var cal = calendar
        cal.timeZone = timeZone

        let meetingDatesByWeekStart: [Date: [Date]] = {
            var out: [Date: [Date]] = [:]
            out.reserveCapacity(16)
            for date in meetingDates {
                guard let interval = cal.dateInterval(of: .weekOfYear, for: date) else { continue }
                out[interval.start, default: []].append(date)
            }
            return out
        }()

        let firstMeetingDate = meetingDates[0]

        let weekAnchor = cal.dateInterval(of: .weekOfYear, for: firstMeetingDate)?.start ?? firstMeetingDate

        func iso(_ d: Date) -> String { SyllabusScheduleParsing.isoDate(d) }

        func pickMeetingDate(week: Int, weekday: SyllabusWeekday?) -> Date? {
            guard week >= 1 else { return nil }
            guard let weekStart = cal.date(byAdding: .day, value: (week - 1) * 7, to: weekAnchor) else { return nil }

            if let weekday {
                // Date for that weekday in this calendar week.
                let target = SyllabusScheduleParsing.date(inSameWeekAs: weekStart, weekday: weekday, calendar: cal)
                if let target, target >= startDate, target <= endDate {
                    if meetingDaysSet.isEmpty || meetingDaysSet.contains(weekday) {
                        return target
                    }
                }
            }

            // Fallback: first meeting day in that week.
            let intervalStart = cal.dateInterval(of: .weekOfYear, for: weekStart)?.start ?? weekStart
            let candidates = meetingDatesByWeekStart[intervalStart] ?? []

            if candidates.isEmpty {
                // If meetingDates didn't land in this week (e.g., short course), pick nearest after week start.
                return meetingDates.first(where: { $0 >= weekStart })
            }

            return candidates.min()
        }

        func pickMeetingDate(meetingNumber: Int) -> Date? {
            guard meetingNumber >= 1, meetingNumber <= meetingDates.count else { return nil }
            return meetingDates[meetingNumber - 1]
        }

        var out: [SyllabusEvent] = []
        out.reserveCapacity(events.count)

        var inferredCount = 0

        for event in events {
            // Keep explicitly dated events.
            if let d = event.date, !d.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                out.append(event)
                continue
            }

            // Try to infer.
            var inferred: Date?

            let combined = (event.title + " " + (event.notes ?? ""))

            let inferredWeek = event.week ?? SyllabusScheduleParsing.extractWeekNumber(from: combined)
            let inferredWeekday = event.weekday ?? SyllabusScheduleParsing.extractWeekday(from: combined)
            let inferredMeetingNumber = event.meetingNumber ?? SyllabusScheduleParsing.extractMeetingNumber(from: combined)

            if inferred == nil, let inferredWeek {
                inferred = pickMeetingDate(week: inferredWeek, weekday: inferredWeekday)
            }

            if inferred == nil, let inferredMeetingNumber {
                inferred = pickMeetingDate(meetingNumber: inferredMeetingNumber)
            }

            if let inferred {
                var ev = event
                ev.date = iso(inferred)
                ev.dateInferred = true
                // Inferred week-based events are always all-day until the user picks their
                // section in the section picker, which applies the correct meeting time.
                if ev.allDay == nil {
                    ev.allDay = (ev.time == nil)
                }
                out.append(ev)
                inferredCount += 1
            } else {
                out.append(event)
            }
        }

        if inferredCount > 0 {
            warnings.append("Inferred \(inferredCount) event date(s) from the course meeting schedule.")
        }

        return .init(events: out, warnings: warnings)
    }
}

// MARK: - Parsing helpers

enum SyllabusScheduleParsing {
    private static let weekdayWordRegex = try? NSRegularExpression(
        pattern: #"\b(mon(?:day)?|tue(?:s|sday)?|wed(?:nesday)?|thu(?:r|rs|rsday)?|fri(?:day)?|sat(?:urday)?|sun(?:day)?)\b"#,
        options: [.caseInsensitive]
    )
    private static let slashWeekdayRegex = try? NSRegularExpression(
        pattern: #"\b[mwtf](?:\s*/\s*[mwtf]){1,3}\b"#,
        options: []
    )
    private static let timeRange24Regex = try? NSRegularExpression(
        pattern: #"\b(\d{1,2}):(\d{2})\s*(?:-|–|—|to)\s*(\d{1,2}):(\d{2})\b"#,
        options: [.caseInsensitive]
    )
    private static let timeRange12Regex = try? NSRegularExpression(
        pattern: #"\b(\d{1,2})(?::(\d{2}))?\s*(am|pm)\s*(?:-|–|—|to)\s*(\d{1,2})(?::(\d{2}))?\s*(am|pm)\b"#,
        options: [.caseInsensitive]
    )
    private static let weekNumberRegex = try? NSRegularExpression(
        pattern: #"\b(?:week|wk)\s*(\d{1,2})\b"#,
        options: [.caseInsensitive]
    )
    private static let meetingNumberRegex = try? NSRegularExpression(
        pattern: #"\b(?:lecture|lec\.?|class|meeting)\s*(\d{1,3})\b"#,
        options: [.caseInsensitive]
    )
    /// Matches space-separated day-letter tokens: "M W F", "T Th", "M W Th".
    /// Alternatives ordered longest-first (tu/th before t) to avoid ambiguity.
    private static let spaceWeekdayRegex = try? NSRegularExpression(
        pattern: #"(?<![a-z])(?:tu|th|m|w|f|t)(?:\s+(?:tu|th|m|w|f|t)){1,5}(?![a-z])"#,
        options: [.caseInsensitive]
    )

    static func parseISODate(_ iso: String, calendar: Calendar, timeZone: TimeZone) -> Date? {
        let parts = iso.split(separator: "-")
        guard parts.count == 3,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else { return nil }
        var cal = calendar
        cal.timeZone = timeZone
        var dc = DateComponents()
        dc.year = y
        dc.month = m
        dc.day = d
        dc.hour = 0
        dc.minute = 0
        dc.second = 0
        return cal.date(from: dc)
    }

    static func isoDate(_ d: Date) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.autoupdatingCurrent
        let comps = cal.dateComponents([.year, .month, .day], from: d)
        guard let y = comps.year, let m = comps.month, let day = comps.day else { return "" }
        return String(format: "%04d-%02d-%02d", y, m, day)
    }

    static func generateMeetingDates(
        startDate: Date,
        endDate: Date,
        meetingDays: Set<SyllabusWeekday>,
        calendar: Calendar,
        timeZone: TimeZone
    ) -> [Date] {
        var cal = calendar
        cal.timeZone = timeZone

        // If meeting days are unknown, we can’t safely generate.
        guard !meetingDays.isEmpty else { return [] }

        var out: [Date] = []
        var current = startDate

        while current <= endDate {
            let weekday = cal.component(.weekday, from: current)
            if meetingDays.contains(where: { $0.calendarWeekday == weekday }) {
                out.append(current)
            }
            guard let next = cal.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }

        return out
    }

    static func date(inSameWeekAs anyDateInWeek: Date, weekday: SyllabusWeekday, calendar: Calendar) -> Date? {
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: anyDateInWeek) else { return nil }
        // Find first occurrence of that weekday within the week interval.
        var current = interval.start
        while current < interval.end {
            if calendar.component(.weekday, from: current) == weekday.calendarWeekday {
                return current
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }
        return nil
    }

    static func parseWeekdays(from s: String) -> [SyllabusWeekday] {
        let lower = s.lowercased()
        var days = Set<SyllabusWeekday>()

        // Common compact patterns.
        if lower.contains("mwf") { days.formUnion([.mon, .wed, .fri]) }
        if lower.contains("tth") || lower.contains("t/th") || lower.contains("t,th") { days.formUnion([.tue, .thu]) }

        // Slash-separated: M/W, M/W/F
        if let re = slashWeekdayRegex {
            let range = NSRange(lower.startIndex..., in: lower)
            if re.firstMatch(in: lower, options: [], range: range) != nil {
                if lower.contains("m") { days.insert(.mon) }
                if lower.contains("w") { days.insert(.wed) }
                // "t" can mean Tue; "th" handled separately.
                if lower.contains("t") { days.insert(.tue) }
                if lower.contains("f") { days.insert(.fri) }
            }
        } else if lower.range(of: #"\b[mwtf](?:\s*/\s*[mwtf]){1,3}\b"#, options: .regularExpression) != nil {
            if lower.contains("m") { days.insert(.mon) }
            if lower.contains("w") { days.insert(.wed) }
            // "t" can mean Tue; "th" handled separately.
            if lower.contains("t") { days.insert(.tue) }
            if lower.contains("f") { days.insert(.fri) }
        }

        // Space-separated single/double-letter tokens: "M W F", "T Th", "M W Th".
        // Only run if the slash/compact passes haven't already populated days,
        // so we don't double-insert from e.g. "MWF" already handled above.
        if days.isEmpty, let re = spaceWeekdayRegex {
            let range = NSRange(lower.startIndex..., in: lower)
            if let m = re.firstMatch(in: lower, options: [], range: range),
               let r = Range(m.range, in: lower) {
                let tokens = String(lower[r]).components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                for token in tokens {
                    switch token {
                    case "m":  days.insert(.mon)
                    case "tu": days.insert(.tue)
                    case "t":  days.insert(.tue)
                    case "th": days.insert(.thu)
                    case "w":  days.insert(.wed)
                    case "f":  days.insert(.fri)
                    default:   break
                    }
                }
            }
        }

        // Full/abbrev weekday words.
        if let re = weekdayWordRegex {
            let range = NSRange(lower.startIndex..., in: lower)
            for m in re.matches(in: lower, options: [], range: range) {
                guard let r = Range(m.range(at: 1), in: lower) else { continue }
                let w = String(lower[r])
                if w.hasPrefix("mon") { days.insert(.mon) }
                else if w.hasPrefix("tue") { days.insert(.tue) }
                else if w.hasPrefix("wed") { days.insert(.wed) }
                else if w.hasPrefix("thu") { days.insert(.thu) }
                else if w.hasPrefix("fri") { days.insert(.fri) }
                else if w.hasPrefix("sat") { days.insert(.sat) }
                else if w.hasPrefix("sun") { days.insert(.sun) }
            }
        }

        // Preserve a reasonable ordering.
        let order: [SyllabusWeekday] = [.mon, .tue, .wed, .thu, .fri, .sat, .sun]
        return order.filter { days.contains($0) }
    }

    static func parseTimeRange(from s: String) -> (String, String)? {
        // Examples:
        // - "2:00 PM - 3:20 PM"
        // - "2:00PM to 3:20PM"
        // - "14:00-15:20"
        let lower = s.lowercased()

        // 24h format.
        if let re24 = timeRange24Regex {
            let range = NSRange(lower.startIndex..., in: lower)
            if let m = re24.firstMatch(in: lower, options: [], range: range),
               let h1 = Range(m.range(at: 1), in: lower).flatMap({ Int(lower[$0]) }),
               let m1 = Range(m.range(at: 2), in: lower).flatMap({ Int(lower[$0]) }),
               let h2 = Range(m.range(at: 3), in: lower).flatMap({ Int(lower[$0]) }),
               let m2 = Range(m.range(at: 4), in: lower).flatMap({ Int(lower[$0]) }) {
                let a = String(format: "%02d:%02d", h1, m1)
                let b = String(format: "%02d:%02d", h2, m2)
                return (a, b)
            }
        }

        // 12h format.
        if let re12 = timeRange12Regex {
            let range = NSRange(lower.startIndex..., in: lower)
            if let m = re12.firstMatch(in: lower, options: [], range: range) {
                func int(_ i: Int) -> Int? {
                    guard let r = Range(m.range(at: i), in: lower) else { return nil }
                    return Int(lower[r])
                }
                func str(_ i: Int) -> String? {
                    guard let r = Range(m.range(at: i), in: lower) else { return nil }
                    return String(lower[r])
                }

                guard let h1 = int(1), let ampm1 = str(3), let h2 = int(4), let ampm2 = str(6) else { return nil }
                let min1 = int(2) ?? 0
                let min2 = int(5) ?? 0

                let a = to24h(hour: h1, minute: min1, ampm: ampm1)
                let b = to24h(hour: h2, minute: min2, ampm: ampm2)
                return (a, b)
            }
        }

        return nil
    }

    private static func to24h(hour: Int, minute: Int, ampm: String) -> String {
        var h = hour % 12
        if ampm == "pm" { h += 12 }
        return String(format: "%02d:%02d", h, minute)
    }

    static func extractWeekNumber(from s: String) -> Int? {
        let lower = s.lowercased()
        let range = NSRange(lower.startIndex..., in: lower)
        guard let m = weekNumberRegex?.firstMatch(in: lower, options: [], range: range),
              let r = Range(m.range(at: 1), in: lower),
              let n = Int(lower[r]) else { return nil }
        return n
    }

    static func extractMeetingNumber(from s: String) -> Int? {
        let lower = s.lowercased()
        let range = NSRange(lower.startIndex..., in: lower)
        guard let m = meetingNumberRegex?.firstMatch(in: lower, options: [], range: range),
              let r = Range(m.range(at: 1), in: lower),
              let n = Int(lower[r]) else { return nil }
        return n
    }

    static func extractWeekday(from s: String) -> SyllabusWeekday? {
        let lower = s.lowercased()
        let map: [(String, SyllabusWeekday)] = [
            ("monday", .mon), ("mon", .mon),
            ("tuesday", .tue), ("tue", .tue),
            ("wednesday", .wed), ("wed", .wed),
            ("thursday", .thu), ("thu", .thu), ("thur", .thu),
            ("friday", .fri), ("fri", .fri),
            ("saturday", .sat), ("sat", .sat),
            ("sunday", .sun), ("sun", .sun),
        ]

        for (needle, day) in map {
            if lower.contains(needle) { return day }
        }

        // Common abbreviations in schedules.
        if lower.contains("tth") || lower.contains("t/th") { return .thu }
        return nil
    }
}
