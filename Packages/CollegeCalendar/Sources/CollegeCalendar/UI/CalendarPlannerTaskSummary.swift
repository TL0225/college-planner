// CalendarPlannerTaskSummary.swift
// Feature: Calendar
// Purpose: Calendar module — CalendarPlannerTaskSummary.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftData

/// Presentation model for planner task rows in Calendar sidebar (Phase 7f).
struct CalendarPlannerTaskSummary: Identifiable, Equatable, Sendable {
    let id: UUID
    let title: String
    let dueDate: Date?

    init(planner task: PlannerTask) {
        id = task.id
        title = task.title
        dueDate = task.dueDate
    }
}

@MainActor
enum CalendarPlannerBridge {
    static func sidebarTasks(
        sidebarDate: Date,
        rangeStart: Date,
        rangeEnd: Date,
        calendar: Calendar,
        collegePersistence: CollegePersistence = .shared
    ) -> [CalendarPlannerTaskSummary] {
        _ = collegePersistence
        let dayStart = calendar.startOfDay(for: sidebarDate)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(86_400)
        return storeSidebarTasks(
            dayStart: dayStart,
            dayEnd: dayEnd,
            rangeStart: rangeStart,
            rangeEnd: rangeEnd
        ) ?? []
    }

    static func resolvePlannerTask(id: UUID, collegePersistence: CollegePersistence = .shared) -> PlannerTask? {
        try? collegePersistence.calendarRepository.fetchPlannerTask(id: id)
    }

    private static func storeSidebarTasks(
        dayStart: Date,
        dayEnd: Date,
        rangeStart: Date,
        rangeEnd: Date
    ) -> [CalendarPlannerTaskSummary]? {
        let repo = CalendarRepository(context: AppDataStore.shared.profileContext)
        guard let tasks = try? repo.fetchTasks(dueFrom: rangeStart, dueBefore: rangeEnd, limit: 200) else {
            return nil
        }
        return sortSidebarTasks(
            tasks
                .filter { task in
                    guard let due = task.dueDate else { return false }
                    return due >= dayStart && due < dayEnd
                }
                .map(CalendarPlannerTaskSummary.init(planner:))
        )
    }

    private static func sortSidebarTasks(_ tasks: [CalendarPlannerTaskSummary]) -> [CalendarPlannerTaskSummary] {
        tasks.sorted { lhs, rhs in
            let ld = lhs.dueDate ?? .distantFuture
            let rd = rhs.dueDate ?? .distantFuture
            if ld != rd { return ld < rd }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }
}
