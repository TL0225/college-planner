// OverviewReadBridge.swift
// Feature: Overview
// Purpose: Overview module — OverviewTaskSummary.
// Data: CollegePersistence / repositories when applicable.

import CollegeCalendar
import CollegeCareer
import Foundation
import SwiftData

struct OverviewTaskSummary: Identifiable, Equatable, Sendable {
    let id: UUID
    let title: String
    let dueDate: Date
    let priority: Int
    let courseCode: String?
    let courseName: String?
}

struct OverviewDocumentSummary: Identifiable, Equatable, Sendable {
    let id: UUID
    let displayName: String
    let fileName: String?
    let lastOpenedAt: Date?
    let addedAt: Date?
}

struct OverviewEventSummary: Identifiable, Equatable, Sendable {
    let id: UUID
    let title: String
    let startDate: Date
    let endDate: Date
    let location: String?
    let courseCode: String?
    let calendarObjectURI: String?

    var stableTimelineID: String { id.uuidString }
}

struct OverviewCareerFollowUpSummary: Identifiable, Equatable, Sendable {
    let id: UUID
    let company: String
    let roleTitle: String
}

/// A single cross-domain "what matters right now" item used by the Overview's
/// top-priority strip. Items are surfaced from existing read bridges (calendar
/// events, task deadlines, career interviews) and ranked by time.
struct OverviewAttentionItem: Identifiable, Equatable, Sendable {
    enum Kind: String, Sendable {
        case event
        case deadline
        case interview
    }

    let id: String
    let kind: Kind
    let title: String
    let subtitle: String?
    /// The concrete date this item refers to (nil when the item is undated, e.g. a
    /// "you have N interviews to prep" rollup). Used for relative-time display.
    let date: Date?
    /// Ordering key. Undated items sort after dated ones.
    let sortDate: Date
}

/// local store-only overview reads (Phase 7f).
@MainActor
enum OverviewReadBridge {
    static func pendingTasks(
        limit: Int = 5,
        collegePersistence: CollegePersistence = .shared
    ) -> [OverviewTaskSummary] {
        _ = collegePersistence
        if let swift = localStorePendingTasks(limit: limit) { return swift }
        return []
    }

    static func recentDocuments(
        limit: Int = 3,
        collegePersistence: CollegePersistence = .shared
    ) -> [OverviewDocumentSummary] {
        _ = collegePersistence
        if let swift = localStoreRecentDocuments(limit: limit) { return swift }
        return []
    }

    static func upcomingEventSummaries(
        days: Int = 8,
        calendarManager: CalendarIntegrationManager,
        collegePersistence: CollegePersistence = .shared
    ) -> [OverviewEventSummary] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let end = cal.date(byAdding: .day, value: days, to: start)
            ?? start.addingTimeInterval(Double(days) * 86_400)
        return storeEventSummaries(from: start, to: end, calendarManager: calendarManager) ?? []
    }

    static func todayEventSummaries(
        calendarManager: CalendarIntegrationManager = CalendarIntegrationManager(),
        collegePersistence: CollegePersistence = .shared
    ) -> [OverviewEventSummary] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let end = cal.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        return upcomingEventSummaries(days: 1, calendarManager: calendarManager, collegePersistence: collegePersistence)
            .filter { $0.startDate >= start && $0.startDate < end }
    }

    static func nextUpcomingEvent(
        calendarManager: CalendarIntegrationManager = CalendarIntegrationManager(),
        collegePersistence: CollegePersistence = .shared
    ) -> OverviewEventSummary? {
        let now = Date()
        if let swift = localStoreNextEvent(after: now, calendarManager: calendarManager) {
            return swift
        }
        return nil
    }

    static func careerFollowUps(
        limit: Int = 3,
        collegePersistence: CollegePersistence = .shared
    ) -> [OverviewCareerFollowUpSummary] {
        _ = collegePersistence
        if let swift = localStoreCareerFollowUps(limit: limit) { return swift }
        return []
    }

    /// Time-ranked, cross-domain "needs attention" list driving the Overview's
    /// priority strip. Deterministic (no scoring heuristics): today's remaining
    /// events + deadlines due within `deadlineWindowDays` + a single interview
    /// rollup, sorted by time and capped to `limit`.
    static func needsAttentionItems(
        limit: Int = 4,
        deadlineWindowDays: Int = 3,
        calendarManager: CalendarIntegrationManager,
        collegePersistence: CollegePersistence = .shared
    ) -> [OverviewAttentionItem] {
        let now = Date()
        var items: [OverviewAttentionItem] = []

        // Today's events that haven't ended yet.
        let events = todayEventSummaries(
            calendarManager: calendarManager,
            collegePersistence: collegePersistence
        )
        .filter { $0.endDate >= now }
        for event in events {
            items.append(
                OverviewAttentionItem(
                    id: "event-\(event.id.uuidString)",
                    kind: .event,
                    title: event.title,
                    subtitle: event.location,
                    date: event.startDate,
                    sortDate: event.startDate
                )
            )
        }

        // Deadlines due within the window.
        let windowEnd = Calendar.current.date(byAdding: .day, value: deadlineWindowDays, to: now)
            ?? now.addingTimeInterval(Double(deadlineWindowDays) * 86_400)
        let deadlines = pendingTasks(limit: 20, collegePersistence: collegePersistence)
            .filter { $0.dueDate <= windowEnd }
        for task in deadlines {
            let course = [task.courseCode, task.courseName]
                .compactMap { value -> String? in
                    guard let value, !value.isEmpty else { return nil }
                    return value
                }
                .joined(separator: " · ")
            items.append(
                OverviewAttentionItem(
                    id: "deadline-\(task.id.uuidString)",
                    kind: .deadline,
                    title: task.title,
                    subtitle: course.isEmpty ? nil : course,
                    date: task.dueDate,
                    sortDate: task.dueDate
                )
            )
        }

        // Career: a single rollup row when interviews are pending.
        let interviewCount = CareerReadBridge.statusCounts()?[.interviewing] ?? 0
        if interviewCount > 0 {
            items.append(
                OverviewAttentionItem(
                    id: "interview-rollup",
                    kind: .interview,
                    title: interviewCount == 1
                        ? "1 interview in progress"
                        : "\(interviewCount) interviews in progress",
                    subtitle: "Prep and follow up",
                    date: nil,
                    sortDate: .distantFuture
                )
            )
        }

        return items
            .sorted { $0.sortDate < $1.sortDate }
            .prefix(limit)
            .map { $0 }
    }

    static func hasPendingTasks(collegePersistence: CollegePersistence = .shared) -> Bool {
        !pendingTasks(limit: 1, collegePersistence: collegePersistence).isEmpty
    }

    static func hasCareerActivity(collegePersistence: CollegePersistence = .shared) -> Bool {
        let total = CareerReadBridge.statusCounts()?.values.reduce(0, +) ?? 0
        if total > 0 { return true }
        return !careerFollowUps(limit: 1, collegePersistence: collegePersistence).isEmpty
    }

    static func academicProfiles(collegePersistence: CollegePersistence = .shared) -> [AcademicProfile] {
        (try? collegePersistence.profileRepository.fetchAcademicProfiles()) ?? collegePersistence.academicProfiles
    }

    private static func localStorePendingTasks(limit: Int) -> [OverviewTaskSummary]? {
        let repo = CalendarRepository(context: AppDataStore.shared.profileContext)
        guard let tasks = try? repo.fetchIncompleteTasksWithDueDate(limit: max(limit, 20)) else { return nil }
        return tasks.prefix(limit).map { task in
            OverviewTaskSummary(
                id: task.id,
                title: task.title,
                dueDate: task.dueDate ?? .distantFuture,
                priority: Int(task.priority),
                courseCode: task.course?.code,
                courseName: task.course?.name
            )
        }
    }

    private static func localStoreRecentDocuments(limit: Int) -> [OverviewDocumentSummary]? {
        let repo = VaultRepository(context: AppDataStore.shared.profileContext)
        guard (try? repo.hasMirroredVaultDocumentRows()) == true else { return nil }
        guard let docs = try? repo.fetchDocuments(limit: max(limit, 20)) else { return nil }
        let sorted = docs.filter { !$0.isFolder }.sorted { lhs, rhs in
            let lDate = lhs.lastOpenedAt ?? lhs.addedAt
            let rDate = rhs.lastOpenedAt ?? rhs.addedAt
            if lDate != rDate { return lDate > rDate }
            return lhs.fileName.localizedCaseInsensitiveCompare(rhs.fileName) == .orderedAscending
        }
        return sorted.prefix(limit).map { doc in
            OverviewDocumentSummary(
                id: doc.id,
                displayName: doc.customDisplayName ?? doc.fileName,
                fileName: doc.fileName,
                lastOpenedAt: doc.lastOpenedAt,
                addedAt: doc.addedAt
            )
        }
    }

    private static func storeEventSummaries(
        from start: Date,
        to end: Date,
        calendarManager: CalendarIntegrationManager
    ) -> [OverviewEventSummary]? {
        let repo = CalendarRepository(context: AppDataStore.shared.profileContext)
        guard (try? repo.hasMirroredCalendarRows()) == true else { return nil }
        guard let events = try? repo.fetchEvents(from: start, to: end, limit: 200) else { return nil }
        return events.compactMap { mapEvent($0, calendarManager: calendarManager) }
            .filter { $0.startDate >= start && $0.startDate < end }
            .sorted { $0.startDate < $1.startDate }
    }

    private static func localStoreNextEvent(
        after date: Date,
        calendarManager: CalendarIntegrationManager
    ) -> OverviewEventSummary? {
        let repo = CalendarRepository(context: AppDataStore.shared.profileContext)
        guard (try? repo.hasMirroredCalendarRows()) == true else { return nil }
        guard let events = try? repo.fetchEvents(from: date, to: date.addingTimeInterval(86_400 * 365), limit: 200) else {
            return nil
        }
        return events
            .filter { $0.startDate >= date }
            .sorted { $0.startDate < $1.startDate }
            .compactMap { mapEvent($0, calendarManager: calendarManager) }
            .first
    }

    private static func localStoreCareerFollowUps(limit: Int) -> [OverviewCareerFollowUpSummary]? {
        let repo = CareerRepository(context: AppDataStore.shared.profileContext)
        guard (try? repo.hasMirroredCareerApplicationRows()) == true else { return nil }
        guard let rows = try? repo.fetchNetworkingQueue(limit: limit) else { return nil }
        return rows.map {
            OverviewCareerFollowUpSummary(
                id: $0.id,
                company: $0.company ?? "Company",
                roleTitle: $0.title ?? "Role"
            )
        }
    }

    private static func mapEvent(
        _ event: CalendarEvent,
        calendarManager: CalendarIntegrationManager
    ) -> OverviewEventSummary? {
        guard calendarManager.shouldDisplayEvent(event.calendarStoredSnapshot) else { return nil }
        return OverviewEventSummary(
            id: event.id,
            title: event.title,
            startDate: event.startDate,
            endDate: event.endDate,
            location: event.location,
            courseCode: event.course?.code,
            calendarObjectURI: "college-store://calendar-event/\(event.id.uuidString)"
        )
    }
}
