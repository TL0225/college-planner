// AppDataStore+UnitTesting.swift
// Feature: Core/Data
// Purpose: Core/Data persistence — — AppDataStore+UnitTesting.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftData

extension AppDataStore {
    /// Clears the shared in-memory profile store between tests to limit heap growth in the XCTest host process.
    @MainActor
    func clearProfileStoreForUnitTesting() throws {
        guard CollegeTestRuntime.isUnitTestProcess else { return }
        let ctx = profileContext
        try deleteAll(PlannerSemester.self, in: ctx)
        try deleteAll(PlannerPlan.self, in: ctx)
        try deleteAll(PlannerCourse.self, in: ctx)
        try deleteAll(CourseGradingCategory.self, in: ctx)
        try deleteAll(CalendarEvent.self, in: ctx)
        try deleteAll(PlannerTask.self, in: ctx)
        try deleteAll(AcademicProfile.self, in: ctx)
        try deleteAll(Profile.self, in: ctx)
        try deleteAll(Experience.self, in: ctx)
        try deleteAll(Achievement.self, in: ctx)
        try deleteAll(VaultDocument.self, in: ctx)
        try deleteAll(WatchedFolder.self, in: ctx)
        try deleteAll(JobApplication.self, in: ctx)
        try deleteAll(RecruiterContact.self, in: ctx)
        try deleteAll(WorkdayJobPosting.self, in: ctx)
        try deleteAll(CareerEvent.self, in: ctx)
        try deleteAll(FocusBlockRecord.self, in: ctx)
        if ctx.hasChanges {
            try ctx.save()
        }
        releaseActiveCatalogContainerForMemoryPressure()
    }

    private func deleteAll<T: PersistentModel>(_ type: T.Type, in context: ModelContext) throws {
        let objects = try context.fetch(FetchDescriptor<T>())
        for object in objects {
            context.delete(object)
        }
    }
}