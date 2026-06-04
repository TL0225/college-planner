// CourseDashboardReadBridge.swift
// Feature: Courses
// Purpose: Courses module — Payload.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftData

/// local store-only reads for the course dashboard (Phase 7f).
@MainActor
enum CourseDashboardReadBridge {
    struct Payload {
        var course: PlannerCourse?
        var tasks: [PlannerTask]
        var events: [CalendarEvent]
    }

    static func load(
        courseCode: String,
        courseID: UUID?,
        appDataStore: AppDataStore = .shared
    ) -> Payload {
        let normalized = normalizeCourseCode(courseCode)
        let repo = appDataStore.profileRepository

        let plannerCourse: PlannerCourse?
        if let courseID {
            plannerCourse = try? repo.fetchCourse(id: courseID)
        } else {
            plannerCourse = try? repo.fetchCourses(matchingCode: normalized, limit: 1).first
        }
        guard let plannerCourse else {
            return Payload(course: nil, tasks: [], events: [])
        }

        let tasks = (try? repo.fetchTasks(forCourseID: plannerCourse.id, limit: 120)) ?? []
        let events = (try? repo.fetchEvents(forCourseID: plannerCourse.id, limit: 40)) ?? []
        return Payload(course: plannerCourse, tasks: tasks, events: events)
    }

    private static func normalizeCourseCode(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
