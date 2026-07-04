// CalendarFetchQuery.swift
// Feature: Calendar
// Purpose: local-store fetch helpers for cache rebuild (Layer 2 bridge; stays in app target).

import Foundation
import SwiftData

/// Background-safe calendar fetches for cache rebuild.
enum CalendarFetchQuery {
    static func hasMirroredCalendarRows(context: ModelContext) throws -> Bool {
        var descriptor = FetchDescriptor<CalendarEvent>()
        descriptor.fetchLimit = 1
        return try !context.fetch(descriptor).isEmpty
    }

    static func hasMirroredPlannerTaskRows(context: ModelContext) throws -> Bool {
        var descriptor = FetchDescriptor<PlannerTask>()
        descriptor.fetchLimit = 1
        return try !context.fetch(descriptor).isEmpty
    }

    static func fetchEventsOverlapping(
        start: Date,
        end: Date,
        limit: Int,
        context: ModelContext
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

    static func fetchTasks(
        dueFrom start: Date,
        dueBefore end: Date,
        limit: Int,
        context: ModelContext
    ) throws -> [PlannerTask] {
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
}
