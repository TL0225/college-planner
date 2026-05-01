import Foundation

// MARK: - Models (shared by Calendar UI + background cache builder)

enum CalendarEventKind: Hashable, Sendable {
    case deadline
    case classEvent
    case lecture
    case lab
    case extracurricular
    case personal
    case club
    case management
    case computerScience
}

struct CalendarCalEvent: Identifiable, Hashable, Sendable {
    let title: String
    let type: CalendarEventKind
    let isImportant: Bool
    var startDate: Date?
    var endDate: Date?
    var isAllDay: Bool
    var calendarEventID: UUID?
    var calendarObjectURI: String?

    var cacheKey: String {
        let titleKey = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let startKey = Int(startDate?.timeIntervalSince1970 ?? 0)
        let endKey = Int(endDate?.timeIntervalSince1970 ?? 0)
        return "\(titleKey)|\(startKey)|\(endKey)|\(isAllDay)"
    }

    var id: String { cacheKey }
}

struct CalendarLayoutSegment: Identifiable, Hashable, Sendable {
    var id: String {
        "\(sourceKey)|\(columnIndex)|\(columnCount)"
    }
    let sourceKey: String
    var event: CalendarCalEvent
    let columnIndex: Int
    let columnCount: Int
}

// MARK: - Snapshots (Sendable; built on MainActor from Core Data objects)

struct CalendarEventSnapshot: Sendable {
    let title: String
    let start: Date
    let end: Date
    let explicitAllDay: Bool?
    let calendarEventID: UUID?
    let calendarObjectURI: String?
}

struct CalendarTaskSnapshot: Sendable {
    let title: String
    let due: Date
}

// MARK: - Pure cache engine (no SwiftUI / Core Data)

enum CalendarCacheEngine: Sendable {

    struct Result: Sendable {
        let dayEventsByDate: [Date: [CalendarCalEvent]]
        let timedLayoutsByDate: [Date: [CalendarLayoutSegment]]
    }

    /// Visible fetch window for Core Data (overlap-friendly).
    static func fetchWindow(
        currentDate: Date,
        mode: CalendarFetchMode,
        cal: Calendar
    ) -> (start: Date, end: Date) {
        let padDays = 45
        switch mode {
        case .month:
            guard let monthInterval = cal.dateInterval(of: .month, for: currentDate) else {
                return fallbackWindow(for: currentDate, cal: cal, padDays: padDays)
            }
            let start = cal.date(byAdding: .day, value: -padDays, to: monthInterval.start) ?? monthInterval.start
            let end = cal.date(byAdding: .day, value: padDays, to: monthInterval.end) ?? monthInterval.end
            return (start, end)
        case .week:
            guard let weekInterval = cal.dateInterval(of: .weekOfYear, for: currentDate) else {
                return fallbackWindow(for: currentDate, cal: cal, padDays: padDays)
            }
            let start = cal.date(byAdding: .day, value: -7, to: weekInterval.start) ?? weekInterval.start
            let end = cal.date(byAdding: .day, value: 7, to: weekInterval.end) ?? weekInterval.end
            return (start, end)
        case .day:
            let dayStart = cal.startOfDay(for: currentDate)
            let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(86400)
            let start = cal.date(byAdding: .day, value: -3, to: dayStart) ?? dayStart
            let end = cal.date(byAdding: .day, value: 3, to: dayEnd) ?? dayEnd
            return (start, end)
        }
    }

    private static func fallbackWindow(for date: Date, cal: Calendar, padDays: Int) -> (Date, Date) {
        let start = cal.date(byAdding: .day, value: -padDays, to: date) ?? date
        let end = cal.date(byAdding: .day, value: padDays, to: date) ?? date
        return (start, end)
    }

    static func buildCaches(
        events: [CalendarEventSnapshot],
        tasks: [CalendarTaskSnapshot],
        calendar: Calendar
    ) -> Result {
        var buckets: [Date: [CalendarCalEvent]] = [:]

        for ev in events {
            let title = ev.title
            var type: CalendarEventKind = .classEvent
            let lowerTitle = title.lowercased()
            if lowerTitle.contains("mgs") {
                type = .management
            } else if lowerTitle.contains("cse") || lowerTitle.contains("csc") {
                type = .computerScience
            } else if lowerTitle.contains("lec") || lowerTitle.contains("lecture") {
                type = .lecture
            } else if lowerTitle.contains("lab") || lowerTitle.contains("lr") || lowerTitle.contains("recitation") {
                type = .lab
            } else if lowerTitle.contains("meeting") || lowerTitle.contains("club") || lowerTitle.contains("eboard")
                || lowerTitle.contains("bowling")
            {
                type = .extracurricular
            } else if lowerTitle.contains("exam") || lowerTitle.contains("midterm") {
                type = .deadline
            }

            let end = ev.end
            let isAllDayEvent = isAllDayEvent(
                title: title,
                start: ev.start,
                end: end,
                explicitFlag: ev.explicitAllDay,
                calendar: calendar
            )

            if isAllDayEvent && lowerTitle.contains("week") {
                type = .classEvent
            }

            let mapped = CalendarCalEvent(
                title: title,
                type: type,
                isImportant: type == .deadline,
                startDate: ev.start,
                endDate: end,
                isAllDay: isAllDayEvent,
                calendarEventID: ev.calendarEventID,
                calendarObjectURI: ev.calendarObjectURI
            )

            buckets[normalizeDay(ev.start, calendar: calendar), default: []].append(mapped)
        }

        for task in tasks {
            buckets[normalizeDay(task.due, calendar: calendar), default: []].append(
                CalendarCalEvent(
                    title: task.title,
                    type: .deadline,
                    isImportant: true,
                    startDate: task.due,
                    endDate: task.due,
                    isAllDay: true,
                    calendarObjectURI: nil
                )
            )
        }

        var normalizedBuckets: [Date: [CalendarCalEvent]] = [:]
        normalizedBuckets.reserveCapacity(buckets.count)

        for (day, list) in buckets {
            var seen = Set<String>()
            let deduped = list.filter { event in
                let key = event.cacheKey
                if seen.contains(key) { return false }
                seen.insert(key)
                return true
            }
            .sorted {
                if $0.isImportant && !$1.isImportant { return true }
                if !$0.isImportant && $1.isImportant { return false }
                if let s1 = $0.startDate, let s2 = $1.startDate { return s1 < s2 }
                return $0.title < $1.title
            }

            normalizedBuckets[day] = deduped
        }

        var layoutBuckets: [Date: [CalendarLayoutSegment]] = [:]
        layoutBuckets.reserveCapacity(normalizedBuckets.count)
        for (day, list) in normalizedBuckets {
            let timedEvents = list.filter { !$0.isAllDay }
            layoutBuckets[day] = calculateLayout(for: timedEvents, calendar: calendar)
        }

        return Result(dayEventsByDate: normalizedBuckets, timedLayoutsByDate: layoutBuckets)
    }

    private static func normalizeDay(_ date: Date, calendar: Calendar) -> Date {
        calendar.startOfDay(for: date)
    }

    private static func isAllDayEvent(
        title: String,
        start: Date,
        end: Date,
        explicitFlag: Bool?,
        calendar: Calendar
    ) -> Bool {
        if let explicitFlag {
            return explicitFlag
        }

        let duration = end.timeIntervalSince(start)
        let lowerTitle = title.lowercased()
        let startsAtMidnight = calendar.component(.hour, from: start) == 0 && calendar.component(.minute, from: start) == 0
        let endsAtMidnight = calendar.component(.hour, from: end) == 0 && calendar.component(.minute, from: end) == 0

        if duration >= 86000 {
            return true
        }
        if startsAtMidnight && endsAtMidnight && duration >= 3600 {
            return true
        }
        if lowerTitle.contains("all day") || lowerTitle.contains("all-day") {
            return true
        }
        if lowerTitle.contains("first day") || lowerTitle.contains("break") {
            return true
        }

        return false
    }

    private static func eventKey(_ event: CalendarCalEvent) -> String {
        event.cacheKey
    }

    private static func calculateLayout(for events: [CalendarCalEvent], calendar: Calendar) -> [CalendarLayoutSegment] {
        var layouts: [CalendarLayoutSegment] = []
        let sorted = events.sorted { ($0.startDate ?? Date()) < ($1.startDate ?? Date()) }

        var currentCluster: [CalendarCalEvent] = []
        var clusterEndTime: Date = .distantPast

        for ev in sorted {
            guard let start = ev.startDate, let end = ev.endDate else { continue }
            if currentCluster.isEmpty {
                currentCluster.append(ev)
                clusterEndTime = end
            } else {
                if start < clusterEndTime {
                    currentCluster.append(ev)
                    if end > clusterEndTime { clusterEndTime = end }
                } else {
                    layouts.append(contentsOf: layoutCluster(currentCluster, calendar: calendar))
                    currentCluster = [ev]
                    clusterEndTime = end
                }
            }
        }
        if !currentCluster.isEmpty {
            layouts.append(contentsOf: layoutCluster(currentCluster, calendar: calendar))
        }
        return layouts
    }

    private static func layoutCluster(_ events: [CalendarCalEvent], calendar: Calendar) -> [CalendarLayoutSegment] {
        var columns: [Date] = []
        var assignedColumns: [String: Int] = [:]

        let sorted = events.sorted { a, b in
            let aStart = a.startDate ?? .distantPast
            let bStart = b.startDate ?? .distantPast
            if aStart != bStart { return aStart < bStart }
            let aDuration = a.endDate?.timeIntervalSince(a.startDate ?? .distantPast) ?? 0
            let bDuration = b.endDate?.timeIntervalSince(b.startDate ?? .distantPast) ?? 0
            if aDuration != bDuration { return aDuration > bDuration }
            return a.title < b.title
        }

        for event in sorted {
            guard let start = event.startDate, let end = event.endDate else { continue }
            var placed = false
            for (colIndex, colEndTime) in columns.enumerated() {
                if start >= colEndTime {
                    columns[colIndex] = end
                    assignedColumns[eventKey(event)] = colIndex
                    placed = true
                    break
                }
            }
            if !placed {
                columns.append(end)
                assignedColumns[eventKey(event)] = columns.count - 1
            }
        }

        let columnCount = max(1, columns.count)
        var result: [CalendarLayoutSegment] = []

        for event in events {
            let col = assignedColumns[eventKey(event)] ?? 0
            result.append(
                CalendarLayoutSegment(
                    sourceKey: eventKey(event),
                    event: event,
                    columnIndex: col,
                    columnCount: columnCount
                )
            )
        }

        return result
    }
}

/// Month / week / day fetch window (maps from `CalendarView.ViewMode`).
enum CalendarFetchMode: Sendable {
    case month
    case week
    case day
}
