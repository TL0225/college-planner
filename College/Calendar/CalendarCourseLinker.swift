import Foundation
import SwiftUI
import Combine

// MARK: - CalendarCourseLinker
//
// Scans unlinked CalendarEventEntity titles for course codes (e.g. "CSE411", "MGS427"),
// infers the semester from the event dates, then silently finds-or-creates the matching
// SemesterEntity + CourseEntity in Academics and links every matching event to it.
//
// Runs automatically after every Google/Apple calendar sync and can be triggered manually.

@MainActor
final class CalendarCourseLinker: ObservableObject {

    static let shared = CalendarCourseLinker()

    // MARK: - Published state

    @Published var isScanning: Bool = false
    @Published var lastScanDate: Date?
    /// Course codes that were newly created (not just newly linked) during the most recent scan.
    @Published var newCoursesFound: [String] = []

    // MARK: - Init

    private init() {}

    // MARK: - Regex

    /// Universal course-code pattern: 2-4 letters followed by 3-4 digits, then an optional
    /// alphabetic suffix that is consumed but NOT captured (handles "CSE411LEC", "MGS405REC",
    /// "CSE191LR", etc. — the suffix is stripped; only the department+number is kept).
    private static let courseCodeRegex: NSRegularExpression = {
        try! NSRegularExpression(
            pattern: #"\b([A-Za-z]{2,4})\s*(\d{3,4})[A-Za-z]*\b"#,
            options: []
        )
    }()

    /// Short tokens that look like course codes but are common false positives.
    private static let exclusionPrefixes: Set<String> = [
        "AM", "PM", "AD", "BC", "ID", "IT", "AT", "BY", "OR", "IN", "TO",
        "GO", "NO", "OK", "US", "TV", "HD", "USB", "URL", "PDF", "GPA",
        "GPT", "AI", "API", "UI", "UX", "EST", "PST", "CST", "MST"
    ]

    // MARK: - Public Entry Points

    /// Full scan: finds all unlinked events, groups them by course code, applies confidence
    /// scoring, then creates/links. Idempotent — safe to call repeatedly.
    func scanAndLink() async {
        guard !isScanning else { return }
        isScanning = true
        defer {
            isScanning = false
            lastScanDate = Date()
        }

        // Merge any duplicate courses created before the prefix-aware dedup was in place.
        CoreDataManager.shared.mergeCourseDuplicates()

        let unlinked = CoreDataManager.shared.fetchUnlinkedCalendarEvents()
        guard !unlinked.isEmpty else { return }

        // Phase 1: group events by extracted course code
        var groups: [String: [CalendarEventEntity]] = [:]
        for event in unlinked {
            guard let title = event.title, !title.isEmpty,
                  let code = extractCourseCode(from: title) else { continue }
            groups[code, default: []].append(event)
        }
        guard !groups.isEmpty else { return }

        var newlyCrated: [String] = []

        for (code, events) in groups {
            // Phase 2: confidence scoring
            let score = confidence(for: code, events: events)
            guard score >= 0.6 else { continue }

            // Phase 3: semester assignment (plurality vote on event dates)
            guard let (season, year) = majorityVoteSemester(for: events) else { continue }

            // Phase 4: find-or-create semester + course
            let semester = CoreDataManager.shared.findOrCreateSemester(season: season, year: year)
            let (course, isNew) = CoreDataManager.shared.findOrCreateCourse(code: code, in: semester)

            // Phase 5: bulk link
            CoreDataManager.shared.bulkLinkCalendarEvents(events, to: course, semester: semester)

            if isNew { newlyCrated.append(code) }
        }

        // Phase 7: append new codes + notify CalendarView
        if !newlyCrated.isEmpty {
            newCoursesFound.append(contentsOf: newlyCrated)
        }
        CoreDataManager.shared.notifyCalendarDidChange()
    }

    /// Targeted rescan for a specific code+semester: claims all floating events that match.
    /// Call after a user manually adds a course in Academics.
    func scanAndLink(forCode code: String, in semester: SemesterEntity) async {
        let upperCode = code.uppercased()
        let allUnlinked = CoreDataManager.shared.fetchUnlinkedCalendarEvents()
        let (season, year) = (semester.season ?? "Unknown", Int(semester.year))

        // Only claim events whose dates fall within ±1 week of the semester's season/year.
        let matching = allUnlinked.filter { event in
            guard let title = event.title,
                  let extracted = extractCourseCode(from: title) else { return false }
            // Accept if the extracted base code and the stored code share a common prefix
            // (e.g. extracted "CSE191" should match stored code "CSE191LR" and vice versa).
            guard extracted == upperCode
                    || upperCode.hasPrefix(extracted)
                    || extracted.hasPrefix(upperCode) else { return false }
            guard let date = event.startDate else { return false }
            let info = semesterInfo(for: date)
            return info.season == season && info.year == year
        }
        guard !matching.isEmpty else { return }
        CoreDataManager.shared.bulkLinkCalendarEvents(matching, to:
            CoreDataManager.shared.findOrCreateCourse(code: upperCode, in: semester).0,
            semester: semester
        )
        CoreDataManager.shared.notifyCalendarDidChange()
    }

    // MARK: - Private Helpers

    /// Extracts a normalized course code from an event title string.
    /// Returns uppercased code like "CSE411" or nil if no valid code found.
    func extractCourseCode(from title: String) -> String? {
        let range = NSRange(title.startIndex..., in: title)
        let matches = Self.courseCodeRegex.matches(in: title, options: [], range: range)
        for match in matches {
            guard match.numberOfRanges == 3,
                  let prefixRange = Range(match.range(at: 1), in: title),
                  let digitRange  = Range(match.range(at: 2), in: title) else { continue }
            let prefix = String(title[prefixRange]).uppercased()
            let digits = String(title[digitRange]).uppercased()

            // Reject common false-positive prefixes
            if Self.exclusionPrefixes.contains(prefix) { continue }
            // Require prefix length >= 3 OR catalog-validated (caller uses catalog check
            // separately via confidence scoring). Two-letter prefixes like "CS" only pass
            // when 3+ events are present, which the confidence gate handles.
            let code = prefix + digits
            return code
        }
        return nil
    }

    /// Confidence score 0–1 for a (code, events) group.
    private func confidence(for code: String, events: [CalendarEventEntity]) -> Double {
        var score: Double
        switch events.count {
        case 1:      score = 0.35
        case 2:      score = 0.55
        case 3, 4:   score = 0.75
        default:     score = 0.90
        }

        // Catalog bonus
        if CoreDataManager.shared.fetchCatalogCourseForCode(code) != nil {
            score = min(score + 0.15, 1.0)
        }

        // Span bonus: events spread over ≥2 weeks in the same semester
        if eventSpanWeeks(events) >= 2 {
            score = min(score + 0.10, 1.0)
        }
        return score
    }

    /// Number of weeks between oldest and newest event in the group.
    private func eventSpanWeeks(_ events: [CalendarEventEntity]) -> Int {
        let dates = events.compactMap { $0.startDate }
        guard let earliest = dates.min(), let latest = dates.max() else { return 0 }
        let seconds = latest.timeIntervalSince(earliest)
        return Int(seconds / (7 * 86400))
    }

    /// Determines the plurality (season, year) across all event start dates.
    private func majorityVoteSemester(for events: [CalendarEventEntity]) -> (String, Int)? {
        var votes: [String: Int] = [:]
        for event in events {
            guard let date = event.startDate else { continue }
            let info = semesterInfo(for: date)
            let key = "\(info.season)|\(info.year)"
            votes[key, default: 0] += 1
        }
        guard let winner = votes.max(by: { $0.value < $1.value }) else { return nil }
        let parts = winner.key.split(separator: "|")
        guard parts.count == 2, let year = Int(parts[1]) else { return nil }
        return (String(parts[0]), year)
    }

    /// Maps a date to its academic semester label.
    private func semesterInfo(for date: Date) -> (season: String, year: Int) {
        let comps = Calendar.current.dateComponents([.month, .year], from: date)
        let month = comps.month ?? 1
        let year  = comps.year  ?? 2026
        switch month {
        case 1...5:   return ("Spring", year)
        case 6...8:   return ("Summer", year)
        default:      return ("Fall",   year)
        }
    }

}
