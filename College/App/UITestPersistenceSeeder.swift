// UITestPersistenceSeeder.swift
// Feature: App
// Purpose: App module — UITestPersistenceSeeder.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftData

/// Parallel UI-test seed for local store profile partition (Phase 7c).
@MainActor
enum UITestPersistenceSeeder {
    static func seedMinimalPlannerDataIfNeeded() {
        guard UITestLaunchFlags.forcesMainUI, UITestLaunchFlags.seedMinimalPlannerData else { return }

        let context = AppDataStore.shared.profileContext
        let existingPlans = (try? ProfileRepository(context: context).fetchPlans(limit: 1)) ?? []
        guard existingPlans.isEmpty else { return }

        let profile = Profile(name: "UITest Student")
        let plan = PlannerPlan(name: "UITest Plan", type: "Major")
        let semester = PlannerSemester(name: "UITest Fall", year: 2026, season: "Fall", seasonOrder: 1)
        let course = PlannerCourse(code: "UIT 101", name: "UITest Intro", credits: 3)
        semester.plan = plan
        course.semester = semester
        context.insert(profile)
        context.insert(plan)
        context.insert(semester)
        context.insert(course)

        let calendarRepo = CalendarRepository(context: context)
        let existingEvents = (try? calendarRepo.fetchEvents(
            from: Date.distantPast,
            to: Date.distantFuture,
            limit: 5
        )) ?? []
        if existingEvents.isEmpty {
            let start = Date()
            let event = CalendarEvent(
                title: "UITest local store Lecture",
                startDate: start,
                endDate: start.addingTimeInterval(3600)
            )
            context.insert(event)
        }

        let existingTasks = (try? calendarRepo.fetchTasks(dueBefore: Date.distantFuture, limit: 5)) ?? []
        if existingTasks.isEmpty {
            context.insert(PlannerTask(title: "UITest local store Assignment", dueDate: Date()))
        }

        try? context.save()
    }
}
