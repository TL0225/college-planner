// CalendarRepository.swift
// Feature: Core/Data
// Purpose: Core/Data persistence — — CalendarRepository.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftData

/// Bounded local store fetch helpers for calendar events and planner tasks (Phase 7b).
@MainActor
struct CalendarRepository {
    let context: ModelContext

    func fetchEvents(
        from start: Date,
        to end: Date,
        limit: Int = 500
    ) throws -> [CalendarEvent] {
        var descriptor = FetchDescriptor<CalendarEvent>(
            predicate: #Predicate { event in
                event.startDate >= start && event.startDate < end
            },
            sortBy: [SortDescriptor(\.startDate, order: .forward)]
        )
        descriptor.fetchLimit = max(1, limit)
        return try context.fetch(descriptor)
    }

    /// Overlap window used by the calendar grid (`startDate < end && endDate > start`).
    func fetchEventsOverlapping(
        start: Date,
        end: Date,
        limit: Int = 500
    ) throws -> [CalendarEvent] {
        var descriptor = FetchDescriptor<CalendarEvent>(
            predicate: #Predicate { event in
                event.startDate < end && event.endDate > start
            },
            sortBy: [SortDescriptor(\.startDate, order: .forward)]
        )
        descriptor.fetchLimit = max(1, limit)
        return try context.fetch(descriptor)
    }

    func fetchTasks(dueFrom start: Date, dueBefore end: Date, limit: Int = 200) throws -> [PlannerTask] {
        let pageLimit = min(max(limit, 1), 400)
        var descriptor = FetchDescriptor<PlannerTask>(
            predicate: #Predicate { task in
                task.isCompleted == false
            },
            sortBy: [SortDescriptor(\.dueDate, order: .forward)]
        )
        descriptor.fetchLimit = pageLimit * 2
        return Array(
            try context.fetch(descriptor)
                .filter { task in
                    guard let due = task.dueDate else { return false }
                    return due >= start && due < end
                }
                .prefix(pageLimit)
        )
    }

    func fetchEvents(forSemesterID semesterID: UUID, limit: Int = 200) throws -> [CalendarEvent] {
        var descriptor = FetchDescriptor<CalendarEvent>(
            predicate: #Predicate { event in
                event.semester?.id == semesterID
            },
            sortBy: [SortDescriptor(\.startDate, order: .forward)]
        )
        descriptor.fetchLimit = max(1, limit)
        return try context.fetch(descriptor)
    }

    func fetchTasks(dueBefore: Date, limit: Int = 200) throws -> [PlannerTask] {
        var descriptor = FetchDescriptor<PlannerTask>(
            predicate: #Predicate { task in
                task.isCompleted == false
            },
            sortBy: [SortDescriptor(\.dueDate, order: .forward)]
        )
        descriptor.fetchLimit = max(1, limit * 2)
        return Array(
            try context.fetch(descriptor)
                .filter { task in
                    guard let due = task.dueDate else { return false }
                    return due <= dueBefore
                }
                .prefix(max(1, limit))
        )
    }

    func fetchTasks(forSemesterID semesterID: UUID, limit: Int = 120) throws -> [PlannerTask] {
        var descriptor = FetchDescriptor<PlannerTask>(
            predicate: #Predicate { task in
                task.semester?.id == semesterID
            },
            sortBy: [SortDescriptor(\.dueDate, order: .forward)]
        )
        descriptor.fetchLimit = max(1, limit)
        return try context.fetch(descriptor)
    }

    /// Bounded title/notes/location/course search (Phase 4 / 7c).
    func searchEvents(
        query: String,
        semesterID: UUID? = nil,
        limit: Int = 50
    ) throws -> [CalendarEvent] {
        try CalendarSearchQuery.searchEvents(
            query: query,
            semesterID: semesterID,
            limit: limit,
            context: context
        )
    }

    func hasMirroredCalendarRows() throws -> Bool {
        var descriptor = FetchDescriptor<CalendarEvent>()
        descriptor.fetchLimit = 1
        return try !context.fetch(descriptor).isEmpty
    }

    func hasMirroredPlannerTaskRows() throws -> Bool {
        var descriptor = FetchDescriptor<PlannerTask>()
        descriptor.fetchLimit = 1
        return try !context.fetch(descriptor).isEmpty
    }

    func fetchIncompleteTasksWithDueDate(limit: Int = 200) throws -> [PlannerTask] {
        let pageLimit = min(max(limit, 1), 400)
        var descriptor = FetchDescriptor<PlannerTask>(
            predicate: #Predicate { task in
                task.isCompleted == false
            },
            sortBy: [SortDescriptor(\.dueDate, order: .forward)]
        )
        descriptor.fetchLimit = pageLimit * 2
        return Array(
            try context.fetch(descriptor)
                .filter { $0.dueDate != nil }
                .prefix(pageLimit)
        )
    }

    func announcementExists(lmsAnnouncementId: String) -> Bool {
        let id = lmsAnnouncementId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return false }
        var descriptor = FetchDescriptor<CalendarEvent>(
            predicate: #Predicate { event in
                event.lmsAnnouncementId == id
            }
        )
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor).isEmpty == false) ?? false
    }

}