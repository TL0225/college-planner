// CalendarPlannerTaskSummary.swift
// Feature: Calendar
// Purpose: Presentation model for planner task rows in Calendar sidebar.

import Foundation

public struct CalendarPlannerTaskSummary: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let title: String
    public let dueDate: Date?

    public init(task: CalendarPlannerTaskRecord) {
        id = task.id
        title = task.title
        dueDate = task.dueDate
    }

    public init(id: UUID, title: String, dueDate: Date?) {
        self.id = id
        self.title = title
        self.dueDate = dueDate
    }
}

@MainActor
public enum CalendarPlannerBridge {
    public static func sidebarTasks(
        sidebarDate: Date,
        rangeStart: Date,
        rangeEnd: Date,
        calendar: Calendar
    ) -> [CalendarPlannerTaskSummary] {
        let dayStart = calendar.startOfDay(for: sidebarDate)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(86_400)
        guard let repo = CalendarPersistenceAccess.writeRepository,
              let tasks = try? repo.fetchTasks(dueFrom: rangeStart, dueBefore: rangeEnd, limit: 200) else {
            return []
        }
        return sortSidebarTasks(
            tasks
                .filter { task in
                    guard let due = task.dueDate else { return false }
                    return due >= dayStart && due < dayEnd
                }
                .map { CalendarPlannerTaskSummary(task: $0) }
        )
    }

    public static func resolvePlannerTask(id: UUID) -> CalendarPlannerTaskRecord? {
        try? CalendarPersistenceAccess.writeRepository?.fetchPlannerTask(id: id)
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
