// SyllabusHeuristicExtractor.swift
// Feature: SyllabusAI
// Purpose: SyllabusAI module — Extraction.
// Data: CollegePersistence / repositories when applicable.

import Foundation

enum SyllabusHeuristicExtractor {
    private static let dateDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
    private static let gradingRegex = try? NSRegularExpression(
        pattern: #"^(.{3,90}?)(?:\s*[-:–—]\s*|\s+)?\(?\s*(\d{1,3})\s*(?:%|percent)\s*\)?\s*$"#,
        options: [.caseInsensitive]
    )
    private static let topicRegexes: [(NSRegularExpression, Int)] = {
        let specs: [(String, Int)] = [
            (#"\bweek\s*\d{1,2}\b\s*[:\-–—]\s*([^\|•\n\r]{3,90})"#, 1),
            (#"\blecture\s*\d{1,3}\b\s*[:\-–—]\s*([^\|•\n\r]{3,90})"#, 1),
            (#"\b(module|unit|lesson)\s*\d{1,3}\b\s*[:\-–—]\s*([^\|•\n\r]{3,90})"#, 2),
            (#"\btopic(?:s)?\b\s*[:\-–—]\s*([^\|•\n\r]{3,90})"#, 1)
        ]
        return specs.compactMap { pattern, group in
            guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
            return (re, group)
        }
    }()
    private static let topicDateSlashRegex = try? NSRegularExpression(pattern: #"\b\d{1,2}/\d{1,2}(?:/\d{2,4})?\b"#, options: [])
    private static let topicDateIsoRegex = try? NSRegularExpression(pattern: #"\b\d{4}-\d{2}-\d{2}\b"#, options: [])
    private static let whitespaceRegex = try? NSRegularExpression(pattern: #"\s+"#, options: [])
    private static let letterRegex = try? NSRegularExpression(pattern: #"[A-Za-z]"#, options: [])
    private static let emailRegex = try? NSRegularExpression(
        pattern: #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#,
        options: [.caseInsensitive]
    )
    private static let instructorLabelRegex = try? NSRegularExpression(
        pattern: #"(?i)\b(instructor|professor|prof\.|lecturer|faculty)\b\s*[:\-]\s*(.{3,100})$"#,
        options: []
    )
    /// Matches a standalone "Week N" header line (the whole line is just "Week 3", etc.).
    private static let weekHeaderRegex = try? NSRegularExpression(
        pattern: #"^\s*[Ww]eek\s+(\d{1,2})\s*$"#,
        options: []
    )
    /// Matches a bare M/DD or M/DD/YY date line (the whole trimmed line is just a date).
    private static let bareDateRegex = try? NSRegularExpression(
        pattern: #"^\d{1,2}/\d{1,2}(?:/\d{2,4})?$"#,
        options: []
    )
    struct Extraction: Sendable {
        let syllabus: SyllabusData
        let debugSummary: String
    }

    /// Local, deterministic fallback extractor.
    /// Uses `NSDataDetector` for dates and lightweight keyword classification.
    static func extract(from cleanedText: String, defaultYear: Int? = nil) -> Extraction {
        let text = cleanedText
        let (grading, gradingWarnings) = extractGrading(from: text)
        // Extract schedule first so meeting days are available for per-day expansion.
        let scheduleExtraction = SyllabusScheduleExtractor.extract(from: text, defaultYear: defaultYear)
        let (events, eventWarnings, debugDates) = extractEvents(from: text, defaultYear: defaultYear)
        let stackedEvents = extractStackedWeekCalendar(from: text, defaultYear: defaultYear)

        // Merge: stacked events carry richer week context; use them as the primary source
        // and backfill any NSDataDetector events that the stacked pass missed.
        var mergedEvents: [SyllabusEvent]
        if !stackedEvents.isEmpty {
            var mergedKeys = Set<String>()
            // Track dates already claimed by the stacked pass to suppress generic
            // "Syllabus Date" placeholders from the NSDataDetector pass for those same dates.
            var stackedDates = Set<String>()
            mergedEvents = stackedEvents
            for ev in stackedEvents {
                mergedKeys.insert("\(ev.title.lowercased())|\(ev.kind.rawValue)|\(ev.date ?? "")")
                if let d = ev.date, !d.isEmpty {
                    stackedDates.insert(d)
                    // For ranged events ("2026-03-16..2026-03-21"), also record the start
                    // date so bare NSDataDetector events for the range's first day are
                    // suppressed and don't appear as duplicates after sorting.
                    if d.contains(".."), let start = d.components(separatedBy: "..").first {
                        stackedDates.insert(start)
                    }
                }
            }
            for ev in events {
                // Suppress generic placeholders whenever stacked parsing is active.
                if isGenericPlaceholderTitle(ev.title) {
                    continue
                }
                let k = "\(ev.title.lowercased())|\(ev.kind.rawValue)|\(ev.date ?? "")"
                if !mergedKeys.contains(k) {
                    mergedEvents.append(ev)
                    mergedKeys.insert(k)
                }
            }
        } else {
            mergedEvents = events
        }

        // Expand weekly topic events to one per meeting day, then sort chronologically.
        mergedEvents = expandTopicEvents(mergedEvents,
                                         meetingDays: scheduleExtraction.schedule?.meetingDays)

        let (instructor, instructorWarnings) = extractInstructor(from: text)

        var warnings: [String] = []
        warnings.append(contentsOf: gradingWarnings)
        warnings.append(contentsOf: eventWarnings)
        if !stackedEvents.isEmpty {
            warnings.append("Stacked week-calendar pass found \(stackedEvents.count) events in week blocks.")
        }
        warnings.append(contentsOf: instructorWarnings)
        warnings.append(contentsOf: scheduleExtraction.warnings)

        let debug = "dates_detected=\(debugDates) grading_items=\(grading.count) events=\(mergedEvents.count)"
        return .init(
            syllabus: .init(
                grading: grading,
                events: mergedEvents,
                instructor: instructor,
                schedule: scheduleExtraction.schedule,
                sections: scheduleExtraction.sections.isEmpty ? nil : scheduleExtraction.sections,
                warnings: warnings.isEmpty ? nil : warnings
            ),
            debugSummary: debug
        )
    }

    // MARK: - Grading

    private static func extractGrading(from text: String) -> ([SyllabusGradingItem], [String]) {
        // Heuristic: look for lines like:
        // - "Homework 20%"
        // - "Midterm: 30%"
        // - "Final Exam - 40%"
        // - "Quiz/Participation (10%)"
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        // Note: avoid `\b` here because `%`/`)` are non-word characters and many real syllabi
        // end the line with ")" (e.g., "Homework (30%)").
        var items: [SyllabusGradingItem] = []
        var seenNames = Set<String>()

        for line in lines {
            guard let re = gradingRegex else { break }
            let range = NSRange(line.startIndex..., in: line)
            guard let m = re.firstMatch(in: line, options: [], range: range) else { continue }
            guard let nameRange = Range(m.range(at: 1), in: line),
                  let pctRange = Range(m.range(at: 2), in: line) else { continue }

            var name = String(line[nameRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            name = name.trimmingCharacters(in: CharacterSet(charactersIn: "-:–—()[]"))
                .trimmingCharacters(in: .whitespacesAndNewlines)

            let pct = Double(String(line[pctRange]))
            let key = name.lowercased()
            guard !name.isEmpty, !seenNames.contains(key) else { continue }
            // Avoid obvious non-grading table headers like "Score (x)".
            if key == "score" || key.hasPrefix("score ") { continue }
            seenNames.insert(key)

            items.append(.init(name: name, weightPercent: pct, notes: nil))
        }

        // If we found suspicious totals, warn but do not fail.
        let total = items.compactMap(\.weightPercent).reduce(0, +)
        var warnings: [String] = []
        if total > 0, total < 90 || total > 110 {
            warnings.append("Grading weights may be incomplete (sum=\(Int(total))%).")
        }

        return (items, warnings)
    }

    // MARK: - Events

    private static func extractEvents(from text: String, defaultYear: Int?) -> ([SyllabusEvent], [String], Int) {
        guard let detector = dateDetector else { return ([], ["Date detector unavailable."], 0) }

        let ns = text as NSString
        let matches = detector.matches(in: text, options: [], range: NSRange(location: 0, length: ns.length))

        var events: [SyllabusEvent] = []
        var warnings: [String] = []
        var seen = Set<String>()

        for match in matches {
            guard let date = match.date else { continue }

            // Capture the line (and optionally a neighbor line) containing the date.
            // This avoids contaminating the classification with unrelated text elsewhere in the document.
            let context = lineContextSnippet(ns, range: match.range)

            // Avoid pulling in dates that are about subscriptions/payments/access codes.
            guard isLikelyCourseCalendarContext(context) else { continue }

            let title = inferTitle(from: context)
            let kind = inferKind(from: context)

            // Normalize to YYYY-MM-DD (or a range) in local time.
            let normalized: String
            if match.duration > 0 {
                var s = isoDate(date)
                var e = isoDate(date.addingTimeInterval(match.duration))
                // Ensure start ≤ end (YYYY-MM-DD strings sort lexicographically).
                if s > e { swap(&s, &e) }
                normalized = s == e ? s : "\(s)..\(e)"
            } else {
                normalized = isoDate(date)
            }

            let key = "\(title.lowercased())|\(kind.rawValue)|\(normalized)"
            guard !seen.contains(key) else { continue }
            seen.insert(key)

            // If detector gave a time, keep it (best-effort).
            let time = isoTimeIfMeaningful(date)

            events.append(.init(
                title: title,
                kind: kind,
                date: normalized,
                time: time,
                allDay: time == nil,
                notes: context,
                sourcePage: nil
            ))
        }

        if events.isEmpty {
            warnings.append("No dates detected by heuristic parser.")
        }

        return (events, warnings, matches.count)
    }

    // MARK: - Stacked Week Calendar

    /// Parses syllabi that use the "Week N / topic / date" stacked multi-line format:
    ///
    ///   Week 1
    ///   Course overview, Boolean Logic
    ///   1/21
    ///   Week 2
    ///   Boolean Logic
    ///   1/26
    ///   Last day to drop/add, Wednesday, January 28
    ///   Week 8
    ///   Midterm Exam, Monday, March 9
    ///   3/9
    ///
    /// For each week block:
    ///  - Bare "M/DD" lines become the anchor date for that week's lecture events.
    ///  - Lines with an NSDataDetector-parseable date are extracted as milestone events.
    ///  - Remaining lines become lecture-topic events tagged with the week number.
    private static func extractStackedWeekCalendar(from text: String, defaultYear: Int?) -> [SyllabusEvent] {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        // Group lines under their "Week N" headers.
        struct WeekGroup { let weekNum: Int; var lines: [String] }
        var groups: [WeekGroup] = []
        var currentWeek: Int? = nil
        var currentLines: [String] = []

        for line in lines {
            guard !line.isEmpty else { continue }

            if let re = weekHeaderRegex {
                let range = NSRange(line.startIndex..., in: line)
                if let m = re.firstMatch(in: line, options: [], range: range),
                   let r = Range(m.range(at: 1), in: line),
                   let num = Int(line[r]) {
                    if let wk = currentWeek {
                        groups.append(WeekGroup(weekNum: wk, lines: currentLines))
                    }
                    currentWeek = num
                    currentLines = []
                    continue
                }
            }

            if currentWeek != nil {
                // Detect all-caps boilerplate headers: 2+ uppercase-only words,
                // total length ≥ 10, no lowercase letters.
                let words = line.split(separator: " ").filter { !$0.isEmpty }
                let isBoilerplateHeader = line.count >= 10
                    && line == line.uppercased()
                    && words.count >= 2
                    && words.allSatisfy { $0.contains(where: { $0.isLetter }) }
                if isBoilerplateHeader {
                    // Finalise current week with the lines collected so far.
                    if let wk = currentWeek, !currentLines.isEmpty {
                        groups.append(WeekGroup(weekNum: wk, lines: currentLines))
                        currentWeek = nil
                        currentLines = []
                    }
                    break
                }
                currentLines.append(line)
            }
        }
        if let wk = currentWeek, !currentLines.isEmpty {
            groups.append(WeekGroup(weekNum: wk, lines: currentLines))
        }

        guard !groups.isEmpty else { return [] }

        let year = defaultYear ?? Calendar(identifier: .gregorian).component(.year, from: Date())
        let detector = dateDetector
        var events: [SyllabusEvent] = []
        var seen = Set<String>()

        let excludeKeywords = ["subscription", "subscribe", "access code", "activation code",
                               "zybooks", "cengage", "pearson", "fee", "cost", "price", "purchase", "$"]

        // Pattern that identifies pure reference/instructional lines such as
        // "See HUB for exam date", "Check Brightspace for schedule", etc.
        // These are not calendar events, just pointers to external resources.
        let referenceLinePrefixes = ["see hub", "see ub", "see brightspace", "see piazza",
                                     "see course", "see the course", "check ub", "check brightspace",
                                     "posted on", "available on", "visit ", "refer to ",
                                     "will be posted", "will be announced"]

        for group in groups {
            let weekNum = group.weekNum

            // Separate bare M/DD anchor lines from content lines.
            var weekDateISO: String? = nil
            var contentLines: [String] = []

            for line in group.lines {
                let nsLine = line as NSString
                let lineRange = NSRange(location: 0, length: nsLine.length)
                if let re = bareDateRegex, re.firstMatch(in: line, options: [], range: lineRange) != nil {
                    // Parse M/DD or M/DD/YY into ISO – only capture the first date per week.
                    if weekDateISO == nil {
                        let parts = line.split(separator: "/")
                        if parts.count == 2,
                           let month = Int(parts[0]), let day = Int(parts[1]) {
                            weekDateISO = String(format: "%04d-%02d-%02d", year, month, day)
                        } else if parts.count == 3,
                                  let month = Int(parts[0]), let day = Int(parts[1]),
                                  let yr = Int(parts[2]) {
                            let fullYear = yr < 100 ? (yr < 70 ? 2000 + yr : 1900 + yr) : yr
                            weekDateISO = String(format: "%04d-%02d-%02d", fullYear, month, day)
                        }
                    }
                } else {
                    contentLines.append(line)
                }
            }

            for contentLine in contentLines {
                let lower = contentLine.lowercased()
                if excludeKeywords.contains(where: { lower.contains($0) }) { continue }
                // Skip lines that are just pointers to external resources.
                if referenceLinePrefixes.contains(where: { lower.hasPrefix($0) }) { continue }

                // Check whether NSDataDetector finds an explicit date in this line → milestone.
                var milestoneDate: String? = nil
                var milestoneTime: String? = nil

                if let det = detector {
                    let ns = contentLine as NSString
                    let range = NSRange(location: 0, length: ns.length)
                    let matches = det.matches(in: contentLine, options: [], range: range)
                    if let first = matches.first, let d = first.date {
                        milestoneTime = isoTimeIfMeaningful(d)
                        if first.duration > 0 {
                            var s = isoDate(d)
                            var e = isoDate(d.addingTimeInterval(first.duration))
                            // Ensure start ≤ end (YYYY-MM-DD strings sort lexicographically).
                            if s > e { swap(&s, &e) }
                            milestoneDate = s == e ? s : "\(s)..\(e)"
                        } else {
                            milestoneDate = isoDate(d)
                        }
                    }
                }

                let kind  = inferKind(from: contentLine)
                let rawTitle = inferTitle(from: contentLine)
                // If inferTitle fell back to a generic placeholder, promote either the
                // cleaned content line or a week-scoped fallback title.
                let title: String = {
                    let candidate = isGenericPlaceholderTitle(rawTitle)
                        ? (cleanTopicLine(contentLine) ?? rawTitle)
                        : rawTitle
                    if isGenericPlaceholderTitle(candidate) {
                        return cleanTopicLine(contentLine) ?? "Week \(weekNum)"
                    }
                    return candidate
                }()

                if let mDate = milestoneDate {
                    // Milestone with an explicit date on this line.
                    let key = "\(title.lowercased())|\(kind.rawValue)|\(mDate)"
                    guard !seen.contains(key) else { continue }
                    seen.insert(key)
                    events.append(.init(
                        title: title,
                        kind: kind,
                        date: mDate,
                        time: milestoneTime,
                        allDay: milestoneTime == nil,
                        notes: contentLine,
                        week: weekNum
                    ))
                } else {
                    // Lecture-topic event – attach the week anchor date if we have one.
                    let topicTitle = cleanTopicLine(contentLine) ?? title
                    let key = "\(topicTitle.lowercased())|\(kind.rawValue)|\(weekNum)"
                    guard !seen.contains(key) else { continue }
                    seen.insert(key)
                    events.append(.init(
                        title: "Week \(weekNum)",
                        kind: kind,
                        date: weekDateISO,
                        time: nil,
                        allDay: weekDateISO != nil ? true : nil,
                        notes: topicTitle,
                        week: weekNum,
                        dateInferred: weekDateISO != nil ? false : nil
                    ))
                }
            }
        }

        return events
    }

    // MARK: - Weekly Topic Expansion

    /// Expands "Week N" topic events to one event per course meeting day in the same week.
    /// Non-topic events (milestones, exams) are passed through unchanged.
    /// All events are returned sorted chronologically by date.
    private static func expandTopicEvents(
        _ events: [SyllabusEvent],
        meetingDays: [SyllabusWeekday]?
    ) -> [SyllabusEvent] {
        var result: [SyllabusEvent] = []
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!

        // Sort meeting days by offset from Monday so events appear Mon→Wed→Fri order.
        let sortedDays = (meetingDays ?? []).sorted {
            ($0.calendarWeekday - 2 + 7) % 7 < ($1.calendarWeekday - 2 + 7) % 7
        }

        for ev in events {
            // Only expand "Week N" topic events that have a single-day anchor date.
            guard ev.kind == .other,
                  let dateStr = ev.date,
                  !dateStr.contains(".."),
                  ev.title.hasPrefix("Week "),
                  sortedDays.count > 1,
                  let anchorDate = isoDateToDate(dateStr) else {
                result.append(ev)
                continue
            }

            // Find Monday of the anchor date's calendar week.
            let anchorWD = cal.component(.weekday, from: anchorDate)  // 1=Sun, 2=Mon…7=Sat
            let daysFromMonday = (anchorWD - 2 + 7) % 7
            guard let monday = cal.date(byAdding: .day, value: -daysFromMonday, to: anchorDate) else {
                result.append(ev)
                continue
            }

            // One copy per meeting day.
            for day in sortedDays {
                let offset = (day.calendarWeekday - 2 + 7) % 7
                guard let meetingDate = cal.date(byAdding: .day, value: offset, to: monday) else { continue }
                // Use the UTC calendar's own components to format the ISO string,
                // so the result is not shifted by the local timezone offset.
                let dc = cal.dateComponents([.year, .month, .day], from: meetingDate)
                guard let y = dc.year, let m = dc.month, let d = dc.day else { continue }
                let iso = String(format: "%04d-%02d-%02d", y, m, d)
                var copy = ev
                copy.id = UUID()
                copy.date = iso
                copy.weekday = day
                result.append(copy)
            }
        }

        // Sort all events chronologically (ISO date strings sort lexicographically).
        result.sort { ($0.date ?? "") < ($1.date ?? "") }
        return result
    }

    /// Strips bullets, date fragments, and excess whitespace from a raw topic line.
    private static func cleanTopicLine(_ line: String) -> String? {
        var s = line.trimmingCharacters(in: .whitespacesAndNewlines)
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: "-–—•:|"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.count >= 3 else { return nil }
        if let re = topicDateSlashRegex {
            s = replaceAll(re, in: s, with: "")
            s = replaceAll(whitespaceRegex, in: s, with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard s.count >= 3 else { return nil }
        if s.count > 80 { s = String(s.prefix(80)).trimmingCharacters(in: .whitespacesAndNewlines) }
        return s
    }

    private static func isLikelyCourseCalendarContext(_ context: String) -> Bool {
        let s = context.lowercased()

        // Exclude obvious non-course dates.
        let exclude = [
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
        if exclude.contains(where: { s.contains($0) }) {
            return false
        }

        // Accept if there are strong academic signals.
        let include = [
            "exam",
            "midterm",
            "final",
            "quiz",
            "homework",
            "assignment",
            "project",
            "lab",
            "presentation",
            "reading",
            "discussion",
            "due",
            "deadline",
            "submit",
            "no class",
            "holiday",
            "break",
            "week"
        ]
        return include.contains(where: { s.contains($0) })
    }

    private static func contextSnippet(_ ns: NSString, range: NSRange, radius: Int) -> String {
        let start = max(0, range.location - radius)
        let end = min(ns.length, range.location + range.length + radius)
        let r = NSRange(location: start, length: max(0, end - start))
        let raw = ns.substring(with: r)
        let collapsed = replaceAll(whitespaceRegex, in: raw.replacingOccurrences(of: "\n", with: " "), with: " ")
        return collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func lineContextSnippet(_ ns: NSString, range: NSRange) -> String {
        let safeRange = NSRange(location: max(0, range.location), length: max(0, min(range.length, ns.length - max(0, range.location))))

        // Previous newline
        let prevSearch = NSRange(location: 0, length: safeRange.location)
        let prev = ns.range(of: "\n", options: [.backwards], range: prevSearch)
        let lineStart = (prev.location == NSNotFound) ? 0 : prev.location + 1

        // Next newline
        let afterLoc = min(ns.length, safeRange.location + safeRange.length)
        let nextSearch = NSRange(location: afterLoc, length: max(0, ns.length - afterLoc))
        let next = ns.range(of: "\n", options: [], range: nextSearch)
        let lineEnd = (next.location == NSNotFound) ? ns.length : next.location

        var line = ns.substring(with: NSRange(location: lineStart, length: max(0, lineEnd - lineStart)))
        line = replaceAll(
            whitespaceRegex,
            in: line.replacingOccurrences(of: "\n", with: " "),
            with: " "
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        // If the line is very short, include the next line too.
        if line.count < 24, lineEnd < ns.length {
            let nextLineStart = lineEnd + 1
            let nextLineEndSearch = NSRange(location: nextLineStart, length: max(0, ns.length - nextLineStart))
            let nextLineBreak = ns.range(of: "\n", options: [], range: nextLineEndSearch)
            let nextLineEnd = (nextLineBreak.location == NSNotFound) ? ns.length : nextLineBreak.location
            let nextLine = ns.substring(with: NSRange(location: nextLineStart, length: max(0, nextLineEnd - nextLineStart)))
            let nextLineCollapsed = replaceAll(whitespaceRegex, in: nextLine, with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !nextLineCollapsed.isEmpty {
                line = (line + " " + nextLineCollapsed).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        // If still short (e.g. a bare "1/21" date line), also prepend the preceding line so
        // classifiers can see the lecture topic written above the date.
        if line.count < 40, lineStart > 0 {
            let prevSearchRange = NSRange(location: 0, length: max(0, lineStart - 1))
            let prevBreak = ns.range(of: "\n", options: [.backwards], range: prevSearchRange)
            let prevLineStart = (prevBreak.location == NSNotFound) ? 0 : prevBreak.location + 1
            let prevLineLen = max(0, lineStart - 1 - prevLineStart)
            if prevLineLen > 0 {
                let prevLine = ns.substring(with: NSRange(location: prevLineStart, length: prevLineLen))
                let prevCollapsed = replaceAll(whitespaceRegex, in: prevLine, with: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !prevCollapsed.isEmpty {
                    line = (prevCollapsed + " " + line).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }

        return line
    }

    private static func inferKind(from context: String) -> SyllabusEvent.Kind {
        let s = context.lowercased()
        if s.contains("final") { return .final }
        if s.contains("midterm") { return .midterm }
        if s.contains("exam") { return .exam }
        if s.contains("quiz") { return .quiz }
        if s.contains("homework") { return .homework }
        if s.contains("assignment") { return .assignment }
        if s.contains("project") { return .project }
        if s.contains("lab") { return .lab }
        if s.contains("presentation") { return .presentation }
        if s.contains("reading") { return .reading }
        return .other
    }

    private static func inferTitle(from context: String) -> String {
        // Prefer an explicit keyword phrase if present.
        let s = context
        let lower = s.lowercased()

        let candidates: [(String, String)] = [
            ("final exam", "Final Exam"),
            ("final", "Final"),
            ("midterm", "Midterm"),
            ("exam", "Exam"),
            ("quiz", "Quiz"),
            ("homework", "Homework Due"),
            ("assignment", "Assignment Due"),
            ("project", "Project Due"),
            ("lab", "Lab"),
            ("presentation", "Presentation"),
            ("reading", "Reading"),
        ]

        for (needle, title) in candidates {
            if lower.contains(needle) { return title }
        }

        if let topic = extractLikelyTopic(from: s) {
            return topic
        }

        return "Syllabus Date"
    }

    private static func isGenericPlaceholderTitle(_ value: String) -> Bool {
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return normalized == "syllabus date" || normalized == "other" || normalized == "topic"
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

        // Fallback: take clause after first ':' or dash if it looks like a topic.
        if let idx = s.firstIndex(where: { $0 == ":" || $0 == "–" || $0 == "—" }) {
            let after = s[s.index(after: idx)...]
            return cleanTopicCandidate(String(after))
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
        x = replaceAll(whitespaceRegex, in: x, with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard x.count >= 3 else { return nil }
        if let re = letterRegex {
            let range = NSRange(x.startIndex..., in: x)
            guard re.firstMatch(in: x, options: [], range: range) != nil else { return nil }
        } else {
            guard x.range(of: #"[A-Za-z]"#, options: .regularExpression) != nil else { return nil }
        }

        let lower = x.lowercased()
        if lower.contains("subscription") || lower.contains("access code") || lower.contains("payment") || lower.contains("fee") {
            return nil
        }

        if x.count > 80 {
            x = String(x.prefix(80)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return x
    }

    private static func isoDateToDate(_ iso: String) -> Date? {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = TimeZone(identifier: "UTC")
        return fmt.date(from: iso)
    }

    private static func isoDate(_ date: Date) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.autoupdatingCurrent
        let comps = cal.dateComponents([.year, .month, .day], from: date)
        guard let y = comps.year, let m = comps.month, let d = comps.day else { return "" }
        return String(format: "%04d-%02d-%02d", y, m, d)
    }

    private static func replaceAll(_ regex: NSRegularExpression?, in s: String, with replacement: String) -> String {
        guard let regex else { return s }
        let range = NSRange(s.startIndex..., in: s)
        return regex.stringByReplacingMatches(in: s, options: [], range: range, withTemplate: replacement)
    }

    private static func isoTimeIfMeaningful(_ date: Date) -> String? {
        // If the detector returned midnight exactly, treat as all-day.
        let cal = Calendar(identifier: .gregorian)
        let comps = cal.dateComponents(in: TimeZone.autoupdatingCurrent, from: date)
        guard let h = comps.hour, let m = comps.minute else { return nil }
        if h == 0 && m == 0 { return nil }

        return String(format: "%02d:%02d", h, m)
    }

    // MARK: - Instructor

    private static func extractInstructor(from text: String) -> (SyllabusInstructor?, [String]) {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.replacingOccurrences(of: "\u{00A0}", with: " ") }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        func cleanedValue(_ raw: String) -> String {
            let collapsed = replaceAll(whitespaceRegex, in: raw, with: " ")
            return collapsed
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "-:–—|•"))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Email
        let email: String? = {
            guard let re = emailRegex else { return nil }
            let range = NSRange(text.startIndex..., in: text)
            guard let m = re.firstMatch(in: text, options: [], range: range),
                  let r = Range(m.range, in: text) else { return nil }
            return String(text[r])
        }()

        // Office hours
        let officeHours: String? = {
            for (idx, line) in lines.enumerated() {
                let lower = line.lowercased()
                guard lower.contains("office hour") else { continue }

                // Common: "Office Hours: Mon 2-4pm".
                if let colon = line.firstIndex(of: ":") {
                    let after = String(line[line.index(after: colon)...])
                    let v = cleanedValue(after)
                    if !v.isEmpty { return v }
                }

                // Sometimes the value is on the next line.
                if idx + 1 < lines.count {
                    let next = cleanedValue(lines[idx + 1])
                    if !next.isEmpty, next.count <= 120 { return next }
                }
            }
            return nil
        }()

        // Name
        let name: String? = {
            for line in lines {
                let range = NSRange(line.startIndex..., in: line)
                if let m = instructorLabelRegex?.firstMatch(in: line, options: [], range: range),
                   let r = Range(m.range(at: 2), in: line) {
                    var candidate = cleanedValue(String(line[r]))
                    if let email, !email.isEmpty {
                        candidate = candidate.replacingOccurrences(of: email, with: "")
                        candidate = cleanedValue(candidate)
                    }
                    // Drop parenthetical titles after the name if the line is long.
                    if let paren = candidate.firstIndex(of: "(") {
                        let head = cleanedValue(String(candidate[..<paren]))
                        if head.count >= 3 { candidate = head }
                    }
                    if !candidate.isEmpty { return candidate }
                }
            }

            // Fallback: try to infer name from an email-adjacent line.
            if let email {
                for line in lines {
                    if line.contains(email) {
                        // E.g., "Jane Doe (jdoe@u.edu)".
                        let withoutEmail = cleanedValue(line.replacingOccurrences(of: email, with: ""))
                        // Heuristic: keep short-ish strings with at least a space (first+last).
                        if withoutEmail.count <= 60, withoutEmail.contains(" "), !withoutEmail.lowercased().contains("office") {
                            return withoutEmail
                        }
                    }
                }
            }
            return nil
        }()

        // Contact method
        let contactMethod: String? = {
            // Look for explicit hints.
            for line in lines {
                let lower = line.lowercased()
                if lower.contains("preferred") && lower.contains("contact") {
                    if let colon = line.firstIndex(of: ":") {
                        let after = cleanedValue(String(line[line.index(after: colon)...]))
                        if !after.isEmpty { return after }
                    }
                }
                if lower.contains("best way") && (lower.contains("reach") || lower.contains("contact")) {
                    return "Email"
                }
            }
            if email != nil { return "Email" }
            return nil
        }()

        let instructor = SyllabusInstructor(name: name, email: email, contactMethod: contactMethod, officeHours: officeHours)
        let hasAny = [instructor.name, instructor.email, instructor.contactMethod, instructor.officeHours].contains(where: { ($0 ?? "").isEmpty == false })
        return (hasAny ? instructor : nil, [])
    }
}
