import Foundation

// MARK: - Public Models

struct SyllabusData: Codable, Sendable {
    var grading: [SyllabusGradingItem]
    var events: [SyllabusEvent]

    /// Optional instructor/professor contact details extracted from the syllabus.
    var instructor: SyllabusInstructor?

    /// Optional course meeting schedule extracted from the syllabus. Used to infer
    /// dates for week-based schedules when explicit dates are not provided.
    var schedule: SyllabusCourseSchedule?

    /// Detected sections (e.g. Section A / Lecture 01 / Recitation B) when the
    /// syllabus lists multiple meeting patterns. Empty or nil means single-section.
    var sections: [SyllabusSection]?

    var warnings: [String]?

    init(
        grading: [SyllabusGradingItem] = [],
        events: [SyllabusEvent] = [],
        instructor: SyllabusInstructor? = nil,
        schedule: SyllabusCourseSchedule? = nil,
        sections: [SyllabusSection]? = nil,
        warnings: [String]? = nil
    ) {
        self.grading = grading
        self.events = events
        self.instructor = instructor
        self.schedule = schedule
        self.sections = sections
        self.warnings = warnings
    }
}

// MARK: - Schedule models

struct SyllabusInstructor: Codable, Hashable, Sendable {
    var name: String?
    var email: String?
    var contactMethod: String?
    var officeHours: String?

    init(
        name: String? = nil,
        email: String? = nil,
        contactMethod: String? = nil,
        officeHours: String? = nil
    ) {
        self.name = name
        self.email = email
        self.contactMethod = contactMethod
        self.officeHours = officeHours
    }
}

enum SyllabusWeekday: String, Codable, CaseIterable, Sendable {
    case mon, tue, wed, thu, fri, sat, sun

    var shortLabel: String {
        switch self {
        case .mon: return "Mon"
        case .tue: return "Tue"
        case .wed: return "Wed"
        case .thu: return "Thu"
        case .fri: return "Fri"
        case .sat: return "Sat"
        case .sun: return "Sun"
        }
    }

    var calendarWeekday: Int {
        // Calendar weekday: 1=Sun, 2=Mon, ... 7=Sat
        switch self {
        case .sun: return 1
        case .mon: return 2
        case .tue: return 3
        case .wed: return 4
        case .thu: return 5
        case .fri: return 6
        case .sat: return 7
        }
    }
}

struct SyllabusCourseSchedule: Codable, Hashable, Sendable {
    /// ISO date preferred: YYYY-MM-DD.
    var startDate: String?
    /// ISO date preferred: YYYY-MM-DD.
    var endDate: String?
    var meetingDays: [SyllabusWeekday]?
    /// Optional 24h time: HH:mm.
    var startTime: String?
    /// Optional 24h time: HH:mm.
    var endTime: String?
    /// IANA time zone identifier (e.g., America/New_York).
    var timeZone: String?

    init(
        startDate: String? = nil,
        endDate: String? = nil,
        meetingDays: [SyllabusWeekday]? = nil,
        startTime: String? = nil,
        endTime: String? = nil,
        timeZone: String? = nil
    ) {
        self.startDate = startDate
        self.endDate = endDate
        self.meetingDays = meetingDays
        self.startTime = startTime
        self.endTime = endTime
        self.timeZone = timeZone
    }
}

/// A single meeting section detected in a syllabus (e.g. "Section A" or "Lecture 01").
/// When a syllabus lists multiple sections, the user can pick theirs so that
/// the appropriate time range is applied to week-based schedule events.
struct SyllabusSection: Codable, Hashable, Identifiable, Sendable {
    /// Short identifier, e.g. "A", "B", "LEC", "01".
    var id: String
    /// Human-readable display label, e.g. "Section A" or "Lecture 01".
    var label: String
    var meetingDays: [SyllabusWeekday]?
    /// 24h time HH:mm.
    var startTime: String?
    /// 24h time HH:mm.
    var endTime: String?
    /// Optional building/room detected in the syllabus (e.g. "Clemens 120").
    var location: String?

    init(
        id: String,
        label: String,
        meetingDays: [SyllabusWeekday]? = nil,
        startTime: String? = nil,
        endTime: String? = nil,
        location: String? = nil
    ) {
        self.id = id
        self.label = label
        self.meetingDays = meetingDays
        self.startTime = startTime
        self.endTime = endTime
        self.location = location
    }
}

struct SyllabusGradingItem: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var name: String
    var weightPercent: Double?
    var notes: String?

    init(id: UUID = UUID(), name: String, weightPercent: Double? = nil, notes: String? = nil) {
        self.id = id
        self.name = name
        self.weightPercent = weightPercent
        self.notes = notes
    }
}

struct SyllabusEvent: Codable, Identifiable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable {
        case exam
        case midterm
        case final
        case quiz
        case homework
        case assignment
        case project
        case lab
        case reading
        case discussion
        case presentation
        case other
    }

    var id: UUID
    var title: String
    var kind: Kind

    /// ISO date: `YYYY-MM-DD` (preferred) or full ISO-8601.
    /// If missing, the app may infer it from `SyllabusCourseSchedule` + `week`/`weekday`.
    var date: String?

    /// Optional 24h time: `HH:mm`.
    var time: String?

    var allDay: Bool?
    var notes: String?

    /// Optional week number within the course schedule (1-based) when the syllabus is week-based.
    var week: Int?
    /// Optional weekday associated with the item (e.g., "Wed" discussion).
    var weekday: SyllabusWeekday?
    /// Optional 1-based meeting index within the course ("Lecture 12"). Used only as a fallback.
    var meetingNumber: Int?
    /// Whether the date was inferred instead of explicitly stated.
    var dateInferred: Bool?

    /// Optional: source page index (1-based) if available.
    var sourcePage: Int?

    init(
        id: UUID = UUID(),
        title: String,
        kind: Kind,
        date: String? = nil,
        time: String? = nil,
        allDay: Bool? = nil,
        notes: String? = nil,
        week: Int? = nil,
        weekday: SyllabusWeekday? = nil,
        meetingNumber: Int? = nil,
        dateInferred: Bool? = nil,
        sourcePage: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.date = date
        self.time = time
        self.allDay = allDay
        self.notes = notes
        self.week = week
        self.weekday = weekday
        self.meetingNumber = meetingNumber
        self.dateInferred = dateInferred
        self.sourcePage = sourcePage
    }
}

// MARK: - Parsing helpers

enum SyllabusDateParseError: LocalizedError {
    case invalidDate(String)

    var errorDescription: String? {
        switch self {
        case .invalidDate(let raw):
            return "Invalid date: \(raw)"
        }
    }
}

enum SyllabusDateParser {
    nonisolated(unsafe) private static let isoWithFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    nonisolated(unsafe) private static let isoNoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    private static let isoFormatterLock = NSLock()

    private static func parseISODateTime(_ s: String) -> Date? {
        isoFormatterLock.lock()
        defer { isoFormatterLock.unlock() }
        if let d = isoWithFractional.date(from: s) { return d }
        return isoNoFractional.date(from: s)
    }

    static func parseEventDate(
        date: String,
        time: String?,
        calendar: Calendar,
        timeZone: TimeZone
    ) throws -> (start: Date, end: Date, allDay: Bool) {
        var cal = calendar
        cal.timeZone = timeZone

        let trimmedDate = date.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTime = time?.trimmingCharacters(in: .whitespacesAndNewlines)

        // 0) Date ranges: YYYY-MM-DD..YYYY-MM-DD
        if let (startYMD, endYMD) = parseYYYYMMDDRange(trimmedDate) {
            var startDC = DateComponents()
            startDC.year = startYMD.year
            startDC.month = startYMD.month
            startDC.day = startYMD.day
            startDC.hour = 0
            startDC.minute = 0
            startDC.second = 0
            guard let start = cal.date(from: startDC) else { throw SyllabusDateParseError.invalidDate(trimmedDate) }

            var endDC = DateComponents()
            endDC.year = endYMD.year
            endDC.month = endYMD.month
            endDC.day = endYMD.day
            endDC.hour = 0
            endDC.minute = 0
            endDC.second = 0
            guard let endInclusive = cal.date(from: endDC) else { throw SyllabusDateParseError.invalidDate(trimmedDate) }

            // For UI review we use an inclusive end date (same-day for single-day all-day, last day for ranges).
            return (start, endInclusive, true)
        }

        // 1) Preferred: YYYY-MM-DD
        if let comps = parseYYYYMMDD(trimmedDate) {
            if let trimmedTime, let (h, m) = parseHHMM(trimmedTime) {
                var dc = DateComponents()
                dc.year = comps.year
                dc.month = comps.month
                dc.day = comps.day
                dc.hour = h
                dc.minute = m
                dc.second = 0
                guard let start = cal.date(from: dc) else { throw SyllabusDateParseError.invalidDate("\(date) \(trimmedTime)") }
                let end = start.addingTimeInterval(60 * 60) // default 1h
                return (start, end, false)
            } else {
                var dc = DateComponents()
                dc.year = comps.year
                dc.month = comps.month
                dc.day = comps.day
                dc.hour = 0
                dc.minute = 0
                dc.second = 0
                guard let start = cal.date(from: dc) else { throw SyllabusDateParseError.invalidDate(date) }
                return (start, start, true)
            }
        }

        // 2) ISO-8601 date-time
        if let d = parseISODateTime(trimmedDate) {
            return (d, d.addingTimeInterval(60 * 60), false)
        }

        throw SyllabusDateParseError.invalidDate(date)
    }

    private struct YMD { let year: Int; let month: Int; let day: Int }

    private static func parseYYYYMMDD(_ s: String) -> YMD? {
        let parts = s.split(separator: "-")
        guard parts.count == 3,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              y > 1900, (1...12).contains(m), (1...31).contains(d) else { return nil }
        return YMD(year: y, month: m, day: d)
    }

    private static func parseYYYYMMDDRange(_ s: String) -> (YMD, YMD)? {
        let parts = s.components(separatedBy: "..")
        guard parts.count == 2 else { return nil }
        let left = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let right = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        guard let a = parseYYYYMMDD(left), let b = parseYYYYMMDD(right) else { return nil }
        return (a, b)
    }

    private static func parseHHMM(_ s: String) -> (Int, Int)? {
        let parts = s.split(separator: ":")
        guard parts.count == 2,
              let h = Int(parts[0]), let m = Int(parts[1]),
              (0...23).contains(h), (0...59).contains(m) else { return nil }
        return (h, m)
    }
}

// MARK: - Post-processing / normalization

enum SyllabusPostProcessor {
    private static let yearRegex = try? NSRegularExpression(pattern: #"\b(20\d{2})\b"#, options: [])
    private static let monthNameRegex = try? NSRegularExpression(
        pattern: #"\b(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\b\s*(\d{1,2})\b"#,
        options: [.caseInsensitive]
    )
    private static let numericDateRegex = try? NSRegularExpression(
        pattern: #"\b(\d{1,2})/(\d{1,2})(?:/(\d{2,4}))?\b"#,
        options: []
    )
    private static let numericDateRangeRegex = try? NSRegularExpression(
        pattern: #"\b(\d{1,2})/(\d{1,2})\b\s*(?:-|–|—|to)\s*\b(\d{1,2})/(\d{1,2})\b"#,
        options: [.caseInsensitive]
    )
    static func normalize(_ decoded: SyllabusData, sourceText: String?, semesterText: String?) -> SyllabusData {
        var out = decoded

        var warningSet = Set(out.warnings ?? [])
        func addWarning(_ s: String) {
            guard !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            warningSet.insert(s)
        }

        let inferredYear = inferYear(from: semesterText) ?? inferYear(from: sourceText)

        // Best-effort instructor extraction if the model didn't provide it.
        if out.instructor == nil, let sourceText {
            let heuristic = SyllabusHeuristicExtractor.extract(from: sourceText, defaultYear: inferredYear)
            if heuristic.syllabus.instructor != nil {
                out.instructor = heuristic.syllabus.instructor
                addWarning("Recovered instructor contact details via heuristic parsing.")
            }
        }

        // Best-effort schedule extraction if the model didn't provide it.
        if out.schedule == nil, let sourceText {
            let scheduleExtraction = SyllabusScheduleExtractor.extract(from: sourceText, defaultYear: inferredYear)
            if let schedule = scheduleExtraction.schedule {
                out.schedule = schedule
            }
            if !scheduleExtraction.sections.isEmpty {
                out.sections = scheduleExtraction.sections
            }
            for w in scheduleExtraction.warnings {
                addWarning(w)
            }
        }

        // If the LLM returns no grading but the text clearly contains percent weights, recover via heuristic.
        if out.grading.isEmpty, let sourceText {
            let heuristic = SyllabusHeuristicExtractor.extract(from: sourceText, defaultYear: inferredYear)
            if !heuristic.syllabus.grading.isEmpty {
                out.grading = heuristic.syllabus.grading
                addWarning("Recovered grading breakdown via heuristic parsing.")
            }
        }

        var events = out.events

        // Infer missing dates for week-based syllabi using the extracted schedule.
        if let schedule = out.schedule {
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = TimeZone.autoupdatingCurrent
            let filled = SyllabusEventDateAutofiller.autofillDates(events: events, schedule: schedule, calendar: cal, timeZone: TimeZone.autoupdatingCurrent)
            events = filled.events
            for w in filled.warnings {
                addWarning(w)
            }
        }

        // Normalize Spring Break (and similar) into a single all-day range when possible.
        events = events.map { normalizeSpringBreak(event: $0, inferredYear: inferredYear) }

        // Correct obvious wrong dates when the notes contain an explicit month/day.
        events = events.map { correctDateFromNotes(event: $0, inferredYear: inferredYear) }

        // For generic "other" items, attempt to use the syllabus topic (Week/Lecture/Topic) as the title.
        events = events.map { fillTopicTitleFromNotesIfNeeded(event: $0) }

        // Downgrade midterm events that do not explicitly mention "midterm" in their own evidence.
        events = events.map { ev in
            var e = ev
            if e.kind == .midterm {
                let combined = (e.title + " " + (e.notes ?? "")).lowercased()
                if !combined.contains("midterm") {
                    e.kind = combined.contains("exam") ? .exam : .other
                    if e.title.lowercased().contains("midterm") {
                        e.title = e.kind == .exam ? "Exam" : "Syllabus Date"
                    }
                    addWarning("Downgraded a midterm classification that lacked explicit 'midterm' evidence.")
                }
            }
            return e
        }

        // If multiple midterms remain, keep the strongest and downgrade the rest.
        let midtermIndices = events.indices.filter { events[$0].kind == .midterm }
        if midtermIndices.count > 1 {
            let best = midtermIndices.max(by: { score(events[$0]) < score(events[$1]) })
            for idx in midtermIndices where idx != best {
                var e = events[idx]
                let combined = (e.title + " " + (e.notes ?? "")).lowercased()
                e.kind = combined.contains("exam") ? .exam : .other
                if e.title.lowercased().contains("midterm") {
                    e.title = e.kind == .exam ? "Exam" : "Syllabus Date"
                }
                events[idx] = e
            }
            addWarning("Multiple midterms detected; kept the strongest match and downgraded the rest.")
        }

        // Drop obvious non-course dates (subscriptions, payments, access-code windows) that can confuse
        // week-based schedules.
        let beforeDropCount = events.count
        events = events.filter { shouldKeepCalendarItem(event: $0) }
        let dropped = beforeDropCount - events.count
        if dropped > 0 {
            addWarning("Dropped \(dropped) non-course date(s) (e.g., subscriptions/payments/access codes).")
        }

        // Deduplicate events after normalization.
        var seen = Set<String>()
        var deduped: [SyllabusEvent] = []
        deduped.reserveCapacity(events.count)
        for ev in events {
            let dateKey = ev.date?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let key = "\(ev.kind.rawValue)|\(dateKey)|\(ev.title.lowercased())"
            guard seen.insert(key).inserted else { continue }
            deduped.append(ev)
        }

        out.events = deduped
        out.warnings = warningSet.isEmpty ? nil : Array(warningSet).sorted()
        return out
    }

    // MARK: - Helpers

    private static func inferYear(from s: String?) -> Int? {
        guard let s, !s.isEmpty else { return nil }
        let range = NSRange(s.startIndex..., in: s)
        guard let m = yearRegex?.firstMatch(in: s, options: [], range: range),
              let yr = Range(m.range(at: 1), in: s),
              let y = Int(s[yr]) else { return nil }
        return y
    }

    private static func normalizeSpringBreak(event: SyllabusEvent, inferredYear: Int?) -> SyllabusEvent {
        var e = event
        let combined = (e.title + " " + (e.notes ?? "")).lowercased()
        guard combined.contains("spring break") else { return e }

        e.kind = .other
        e.allDay = true
        e.title = "Spring Break"
        e.time = nil

        if let (start, end) = extractLikelyDateRange(from: combined, inferredYear: inferredYear) {
            e.date = "\(start)..\(end)"
        } else if let single = extractLikelySingleDate(from: combined, inferredYear: inferredYear) {
            e.date = single
        }

        return e
    }

    private static func correctDateFromNotes(event: SyllabusEvent, inferredYear: Int?) -> SyllabusEvent {
        var e = event
        let combined = (e.title + " " + (e.notes ?? ""))

        // Only attempt date correction for assessment-ish items.
        guard [.midterm, .final, .exam, .quiz, .assignment, .homework, .project, .lab, .presentation].contains(e.kind) else {
            return e
        }

        // If notes contain an explicit month name + day (e.g., "March 9"), trust that over a likely mis-picked table date.
        if let inferred = extractExplicitMonthNameDate(from: combined, inferredYear: inferredYear) {
            if inferred != e.date {
                e.date = inferred
            }
        }

        return e
    }

    private static func fillTopicTitleFromNotesIfNeeded(event: SyllabusEvent) -> SyllabusEvent {
        var e = event
        guard e.kind == .other else { return e }

        let rawTitle = e.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let titleLower = rawTitle.lowercased()
        guard rawTitle.isEmpty || titleLower == "syllabus date" || titleLower == "other" else { return e }

        let context = (e.notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !context.isEmpty else { return e }

        let contextLower = context.lowercased()
        // Keep canonical closures like Spring Break/holidays as-is.
        if isAcademicClosureContext(contextLower) { return e }
        // Avoid turning commercial admin lines into topics.
        if isNonCourseAccessOrPaymentContext(contextLower) { return e }

        guard let topic = extractLikelyTopic(from: context) else { return e }
        e.title = topic
        return e
    }

    private static let topicRegexes: [(NSRegularExpression, Int)] = {
        let specs: [(String, Int)] = [
            (#"\bweek\s*\d{1,2}\b\s*[:\-–—]\s*([^\|•\n\r]{3,90})"#, 1),
            (#"\blecture\s*\d{1,3}\b\s*[:\-–—]\s*([^\|•\n\r]{3,90})"#, 1),
            (#"\b(module|unit|lesson)\s*\d{1,3}\b\s*[:\-–—]\s*([^\|•\n\r]{3,90})"#, 2),
            (#"\btopic(?:s)?\b\s*[:\-–—]\s*([^\|•\n\r]{3,90})"#, 1),
            (#"\b(chapter|ch\.)\s*\d{1,3}\b\s*[:\-–—]\s*([^\|•\n\r]{3,90})"#, 2)
        ]

        return specs.compactMap { pattern, group in
            guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
            return (re, group)
        }
    }()
    private static let topicDateSlashRegex = try? NSRegularExpression(
        pattern: #"\b\d{1,2}/\d{1,2}(?:/\d{2,4})?\b"#,
        options: []
    )
    private static let topicDateIsoRegex = try? NSRegularExpression(
        pattern: #"\b\d{4}-\d{2}-\d{2}\b"#,
        options: []
    )
    private static let topicMonthNameRegex = try? NSRegularExpression(
        pattern: #"\b(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\b\s*\d{1,2}(?:,\s*20\d{2})?"#,
        options: [.caseInsensitive]
    )
    private static let whitespaceRegex = try? NSRegularExpression(pattern: #"\s+"#, options: [])
    private static let letterRegex = try? NSRegularExpression(pattern: #"[A-Za-z]"#, options: [])

    private static func replaceAll(_ regex: NSRegularExpression?, in s: String, with replacement: String) -> String {
        guard let regex else { return s }
        let range = NSRange(s.startIndex..., in: s)
        return regex.stringByReplacingMatches(in: s, options: [], range: range, withTemplate: replacement)
    }

    private static func extractLikelyTopic(from context: String) -> String? {
        let normalized = context.replacingOccurrences(of: "\u{00A0}", with: " ")
        let s = replaceAll(whitespaceRegex, in: normalized, with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let range = NSRange(s.startIndex..., in: s)
        for (re, group) in topicRegexes {
            guard let m = re.firstMatch(in: s, options: [], range: range),
                  group <= m.numberOfRanges,
                  let r = Range(m.range(at: group), in: s) else { continue }
            if let cleaned = cleanTopicCandidate(String(s[r])) {
                return cleaned
            }
        }

        // Fallback: take the clause after the first ':' or '–' if it looks like a topic.
        if let idx = s.firstIndex(where: { $0 == ":" || $0 == "–" || $0 == "—" }) {
            let after = s[s.index(after: idx)...]
            if let cleaned = cleanTopicCandidate(String(after)) {
                return cleaned
            }
        }

        return nil
    }

    private static func cleanTopicCandidate(_ raw: String) -> String? {
        let normalized = raw.replacingOccurrences(of: "\u{00A0}", with: " ")
        var x = replaceAll(whitespaceRegex, in: normalized, with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-:–—|•"))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove obvious date fragments.
        x = replaceAll(topicDateSlashRegex, in: x, with: "")
        x = replaceAll(topicDateIsoRegex, in: x, with: "")
        x = replaceAll(topicMonthNameRegex, in: x, with: "")

        // Stop at common separators so we don't swallow whole paragraphs.
        if let bar = x.firstIndex(of: "|") { x = String(x[..<bar]) }
        if let bullet = x.firstIndex(of: "•") { x = String(x[..<bullet]) }
        if let dash = x.range(of: " - ") { x = String(x[..<dash.lowerBound]) }

        x = replaceAll(whitespaceRegex, in: x, with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard x.count >= 3 else { return nil }
        // Must contain at least one letter to be a useful topic.
        if let re = letterRegex {
            let range = NSRange(x.startIndex..., in: x)
            guard re.firstMatch(in: x, options: [], range: range) != nil else { return nil }
        } else {
            guard x.range(of: #"[A-Za-z]"#, options: .regularExpression) != nil else { return nil }
        }
        // Avoid returning generic boilerplate.
        let lower = x.lowercased()
        if lower == "week" || lower == "lecture" || lower == "topic" { return nil }
        if lower.contains("subscription") || lower.contains("access code") { return nil }

        if x.count > 80 {
            x = String(x.prefix(80)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return x
    }

    private static func score(_ ev: SyllabusEvent) -> Int {
        let combined = (ev.title + " " + (ev.notes ?? "")).lowercased()
        var s = 0
        if combined.contains("midterm exam") { s += 20 }
        if combined.contains("midterm") { s += 12 }
        if combined.contains("final exam") { s += 10 }
        if combined.contains("exam") { s += 6 }
        if combined.contains("quiz") { s += 4 }
        if extractExplicitMonthNameDate(from: combined, inferredYear: nil) != nil { s += 3 }
        if hasNumericDateMention(combined) { s += 2 }
        return s
    }

    private static func hasNumericDateMention(_ text: String) -> Bool {
        let range = NSRange(text.startIndex..., in: text)
        return numericDateRegex?.firstMatch(in: text, options: [], range: range) != nil
    }

    private static func extractLikelySingleDate(from text: String, inferredYear: Int?) -> String? {
        if let iso = extractExplicitMonthNameDate(from: text, inferredYear: inferredYear) {
            return iso
        }
        return extractExplicitNumericDate(from: text, inferredYear: inferredYear)
    }

    private static func extractLikelyDateRange(from text: String, inferredYear: Int?) -> (String, String)? {
        // Prefer month-name-based ranges (e.g., "March 16 – March 21" or "March 16 - 21").
        if let range = extractExplicitMonthNameDateRange(from: text, inferredYear: inferredYear) {
            return range
        }

        // Fall back to numeric date ranges (e.g., "3/16 - 3/21").
        if let range = extractExplicitNumericDateRange(from: text, inferredYear: inferredYear) {
            return range
        }

        return nil
    }

    private static func extractExplicitMonthNameDate(from text: String, inferredYear: Int?) -> String? {
        let re = monthNameRegex
        let range = NSRange(text.startIndex..., in: text)
        guard let m = re?.firstMatch(in: text, options: [], range: range),
              let mr = Range(m.range(at: 1), in: text),
              let dr = Range(m.range(at: 2), in: text) else { return nil }

        let monthName = String(text[mr]).lowercased()
        guard let month = monthNumber(monthName),
              let day = Int(text[dr]) else { return nil }
        let year = inferredYear ?? inferYear(from: text) ?? Calendar(identifier: .gregorian).component(.year, from: Date())
        return isoDate(year: year, month: month, day: day)
    }

    private static func extractExplicitMonthNameDateRange(from text: String, inferredYear: Int?) -> (String, String)? {
        // If the string contains multiple month-name dates, take the first two.
        guard let re = monthNameRegex else { return nil }

        let nsRange = NSRange(text.startIndex..., in: text)
        let matches = re.matches(in: text, options: [], range: nsRange)
        guard matches.count >= 2 else { return nil }

        func parse(_ m: NSTextCheckingResult) -> (Int, Int)? {
            guard let mr = Range(m.range(at: 1), in: text),
                  let dr = Range(m.range(at: 2), in: text) else { return nil }
            guard let month = monthNumber(String(text[mr]).lowercased()),
                  let day = Int(text[dr]) else { return nil }
            return (month, day)
        }

        guard let a = parse(matches[0]), let b = parse(matches[1]) else { return nil }
        let year = inferredYear ?? inferYear(from: text) ?? Calendar(identifier: .gregorian).component(.year, from: Date())
        guard var start = isoDate(year: year, month: a.0, day: a.1) else { return nil }
        guard var end = isoDate(year: year, month: b.0, day: b.1) else { return nil }
        // Always return (earlier, later) regardless of text order.
        if start > end { swap(&start, &end) }
        return (start, end)
    }

    private static func extractExplicitNumericDate(from text: String, inferredYear: Int?) -> String? {
        let range = NSRange(text.startIndex..., in: text)
        guard let m = numericDateRegex?.firstMatch(in: text, options: [], range: range) else { return nil }
        guard let mr = Range(m.range(at: 1), in: text),
              let dr = Range(m.range(at: 2), in: text) else { return nil }

        let month = Int(text[mr]) ?? 0
        let day = Int(text[dr]) ?? 0
        var year = inferredYear ?? inferYear(from: text)
        if year == nil, m.numberOfRanges >= 4, let yr = Range(m.range(at: 3), in: text) {
            if let y = Int(text[yr]) {
                year = (y < 100) ? (2000 + y) : y
            }
        }
        let finalYear = year ?? Calendar(identifier: .gregorian).component(.year, from: Date())
        return isoDate(year: finalYear, month: month, day: day)
    }

    private static func extractExplicitNumericDateRange(from text: String, inferredYear: Int?) -> (String, String)? {
        let range = NSRange(text.startIndex..., in: text)
        guard let m = numericDateRangeRegex?.firstMatch(in: text, options: [], range: range) else { return nil }
        guard let m1 = Range(m.range(at: 1), in: text),
              let d1 = Range(m.range(at: 2), in: text),
              let m2 = Range(m.range(at: 3), in: text),
              let d2 = Range(m.range(at: 4), in: text) else { return nil }

        let monthA = Int(text[m1]) ?? 0
        let dayA = Int(text[d1]) ?? 0
        let monthB = Int(text[m2]) ?? 0
        let dayB = Int(text[d2]) ?? 0
        let year = inferredYear ?? inferYear(from: text) ?? Calendar(identifier: .gregorian).component(.year, from: Date())
        guard var start = isoDate(year: year, month: monthA, day: dayA),
              var end = isoDate(year: year, month: monthB, day: dayB) else { return nil }
        // Always return (earlier, later) regardless of text order.
        if start > end { swap(&start, &end) }
        return (start, end)
    }

    private static func monthNumber(_ s: String) -> Int? {
        let x = s.lowercased()
        if x.hasPrefix("jan") { return 1 }
        if x.hasPrefix("feb") { return 2 }
        if x.hasPrefix("mar") { return 3 }
        if x.hasPrefix("apr") { return 4 }
        if x == "may" { return 5 }
        if x.hasPrefix("jun") { return 6 }
        if x.hasPrefix("jul") { return 7 }
        if x.hasPrefix("aug") { return 8 }
        if x.hasPrefix("sep") { return 9 }
        if x.hasPrefix("oct") { return 10 }
        if x.hasPrefix("nov") { return 11 }
        if x.hasPrefix("dec") { return 12 }
        return nil
    }

    private static func isoDate(year: Int, month: Int, day: Int) -> String? {
        guard year > 1900, (1...12).contains(month), (1...31).contains(day) else { return nil }
        var dc = DateComponents()
        dc.year = year
        dc.month = month
        dc.day = day
        let cal = Calendar(identifier: .gregorian)
        guard cal.date(from: dc) != nil else { return nil }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    private static func shouldKeepCalendarItem(event: SyllabusEvent) -> Bool {
        // Keep all explicitly-classified academic work.
        if event.kind != .other { return true }

        let combined = (event.title + " " + (event.notes ?? "")).lowercased()

        // Drop commercial/administrative access dates (subscription windows, fees, textbook access codes).
        if isNonCourseAccessOrPaymentContext(combined) {
            return false
        }

        // Keep canonical all-day schedule exceptions.
        if isAcademicClosureContext(combined) {
            return true
        }

        // Keep if the text clearly indicates a course deadline.
        if combined.contains(" due") || combined.contains("due ") || combined.contains("deadline") || combined.contains("submit") {
            return true
        }

        // Drop generic placeholder dates that have no strong academic signal.
        if event.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "syllabus date" {
            return false
        }

        return true
    }

    private static func isNonCourseAccessOrPaymentContext(_ s: String) -> Bool {
        let needles = [
            "subscription",
            "subscribe",
            "cutoff to subscribe",
            "access code",
            "activation code",
            "registration code",
            "zybooks",
            "cengage",
            "pearson",
            "mcgraw",
            "mhe",
            "wiley",
            "tophat",
            "top hat",
            "iclicker",
            "i-clicker",
            "fee",
            "cost",
            "price",
            "purchase",
            "$"
        ]
        return needles.contains(where: { s.contains($0) })
    }

    private static func isAcademicClosureContext(_ s: String) -> Bool {
        let needles = [
            "spring break",
            "break",
            "no class",
            "no classes",
            "holiday",
            "campus closed",
            "classes cancelled",
            "classes canceled",
            "thanksgiving",
            "labor day",
            "memorial day",
            "mlk",
            "martin luther king"
        ]
        return needles.contains(where: { s.contains($0) })
    }
}
