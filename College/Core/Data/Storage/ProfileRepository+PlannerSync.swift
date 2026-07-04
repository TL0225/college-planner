// ProfileRepository+PlannerSync.swift
// Feature: Core/Data
// Purpose: Core/Data persistence — — ProfileRepository+PlannerSync.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftData

extension ProfileRepository {
    func hasMirroredPlannerRows() throws -> Bool {
        var descriptor = FetchDescriptor<PlannerPlan>()
        descriptor.fetchLimit = 1
        return try !context.fetch(descriptor).isEmpty
    }

    func fetchCourses(matchingCode code: String, limit: Int = 20) throws -> [PlannerCourse] {
        let normalized = code
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .uppercased()
        guard !normalized.isEmpty else { return [] }
        var descriptor = FetchDescriptor<PlannerCourse>(
            sortBy: [SortDescriptor(\.sortOrder, order: .forward)]
        )
        descriptor.fetchLimit = min(max(limit * 4, limit), 200)
        return try context.fetch(descriptor).filter { course in
            course.code
                .replacingOccurrences(of: " ", with: "")
                .uppercased()
                .contains(normalized)
        }
        .prefix(max(1, limit))
        .map { $0 }
    }

    func fetchTasks(forCourseID courseID: UUID, limit: Int = 120) throws -> [PlannerTask] {
        var descriptor = FetchDescriptor<PlannerTask>(
            predicate: #Predicate { task in
                task.course?.id == courseID
            },
            sortBy: [SortDescriptor(\.dueDate, order: .forward)]
        )
        descriptor.fetchLimit = max(1, limit)
        return try context.fetch(descriptor)
    }

    func fetchEvents(forCourseID courseID: UUID, limit: Int = 40) throws -> [CalendarEvent] {
        var descriptor = FetchDescriptor<CalendarEvent>(
            predicate: #Predicate { event in
                event.course?.id == courseID
            },
            sortBy: [SortDescriptor(\.startDate, order: .forward)]
        )
        descriptor.fetchLimit = max(1, limit)
        return try context.fetch(descriptor)
    }

    func totalPlannerCourseCount() throws -> Int {
        try context.fetchCount(FetchDescriptor<PlannerCourse>())
    }

}