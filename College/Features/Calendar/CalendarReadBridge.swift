// CalendarReadBridge.swift
// Feature: Calendar
// Purpose: Calendar module — CalendarReadBridge.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftData
import CollegeCalendar

/// local store-only calendar reads for cache rebuild (Phase 7f).
@MainActor
enum CalendarReadBridge {
    static func eventSnapshots(
        rangeStart: Date,
        rangeEnd: Date,
        calendarManager: CalendarIntegrationManager,
        collegePersistence: CollegePersistence = .shared
    ) -> [CalendarEventSnapshot] {
        _ = collegePersistence
        return storeEventSnapshots(
            rangeStart: rangeStart,
            rangeEnd: rangeEnd,
            calendarManager: calendarManager
        ) ?? []
    }

    static func taskSnapshots(
        rangeStart: Date,
        rangeEnd: Date
    ) -> [CalendarTaskSnapshot] {
        return localStoreTaskSnapshots(rangeStart: rangeStart, rangeEnd: rangeEnd) ?? []
    }

    /// Fetches overlapping events on a background `ModelContext` (Phase 3 P0).
    static func eventSnapshotsOffMain(
        rangeStart: Date,
        rangeEnd: Date,
        calendarManager: CalendarIntegrationManager
    ) async -> [CalendarEventSnapshot] {
        let container = await MainActor.run { AppDataStore.shared.profileContainer }
        let visibility = await calendarManager.makeCacheRebuildVisibilityFilter()
        return await Task.detached(priority: .userInitiated) {
            let context = ModelContext(container)
            guard (try? CalendarFetchQuery.hasMirroredCalendarRows(context: context)) == true else {
                return [CalendarEventSnapshot]()
            }
            guard let events = try? CalendarFetchQuery.fetchEventsOverlapping(
                start: rangeStart,
                end: rangeEnd,
                limit: 500,
                context: context
            ) else {
                return [CalendarEventSnapshot]()
            }
            return events.compactMap { event in
                guard visibility.shouldDisplay(event) else { return nil }
                return CalendarEventSnapshot(
                    title: event.title,
                    start: event.startDate,
                    end: event.endDate,
                    explicitAllDay: event.allDay,
                    calendarEventID: event.id,
                    calendarObjectURI: "college-store://calendar-event/\(event.id.uuidString)"
                )
            }
        }.value
    }

    static func taskSnapshotsOffMain(
        rangeStart: Date,
        rangeEnd: Date
    ) async -> [CalendarTaskSnapshot] {
        let container = await MainActor.run { AppDataStore.shared.profileContainer }
        return await Task.detached(priority: .userInitiated) {
            let context = ModelContext(container)
            guard (try? CalendarFetchQuery.hasMirroredPlannerTaskRows(context: context)) == true else {
                return [CalendarTaskSnapshot]()
            }
            guard let tasks = try? CalendarFetchQuery.fetchTasks(
                dueFrom: rangeStart,
                dueBefore: rangeEnd,
                limit: 200,
                context: context
            ) else {
                return [CalendarTaskSnapshot]()
            }
            return tasks.compactMap { task in
                guard let due = task.dueDate else { return nil }
                return CalendarTaskSnapshot(title: task.title, due: due)
            }
        }.value
    }

    private static func storeEventSnapshots(
        rangeStart: Date,
        rangeEnd: Date,
        calendarManager: CalendarIntegrationManager
    ) -> [CalendarEventSnapshot]? {
        let repo = CalendarRepository(context: AppDataStore.shared.profileContext)
        guard (try? repo.hasMirroredCalendarRows()) == true else { return nil }
        guard let events = try? repo.fetchEventsOverlapping(
            start: rangeStart,
            end: rangeEnd,
            limit: 500
        ) else {
            return nil
        }

        return events.compactMap { event in
            guard calendarManager.shouldDisplayEvent(event) else { return nil }
            return CalendarEventSnapshot(
                title: event.title,
                start: event.startDate,
                end: event.endDate,
                explicitAllDay: event.allDay,
                calendarEventID: event.id,
                calendarObjectURI: "college-store://calendar-event/\(event.id.uuidString)"
            )
        }
    }

    private static func localStoreTaskSnapshots(
        rangeStart: Date,
        rangeEnd: Date
    ) -> [CalendarTaskSnapshot]? {
        let repo = CalendarRepository(context: AppDataStore.shared.profileContext)
        guard (try? repo.hasMirroredPlannerTaskRows()) == true else { return nil }
        guard let tasks = try? repo.fetchTasks(
            dueFrom: rangeStart,
            dueBefore: rangeEnd,
            limit: 200
        ) else {
            return nil
        }
        return tasks.compactMap { task in
            guard let due = task.dueDate else { return nil }
            return CalendarTaskSnapshot(title: task.title, due: due)
        }
    }
}
