// ProfilePlannerReadBridge.swift
// Feature: Core/Data
// Purpose: Core/Data persistence — — ProfilePlannerReadBridge.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftData

/// local store-only planner/profile reads (Phase 7f).
@MainActor
enum ProfilePlannerReadBridge {
    static func primaryProfile(appDataStore: AppDataStore = .shared) -> Profile? {
        try? appDataStore.profileRepository.fetchPrimaryProfile()
    }

    static func plans(appDataStore: AppDataStore = .shared) -> [PlannerPlan] {
        (try? appDataStore.profileRepository.fetchPlans(limit: 100)) ?? []
    }

    static func allCoursesAcrossPlans(appDataStore: AppDataStore = .shared) -> [PlannerCourse] {
        let repo = appDataStore.profileRepository
        return plans(appDataStore: appDataStore).flatMap { plan in
            (try? repo.fetchSemesters(forPlanID: plan.id, limit: 200)) ?? []
        }.flatMap { semester in
            (try? repo.fetchCourses(forSemesterID: semester.id, limit: 500)) ?? []
        }
    }

    static func allSemestersAcrossPlans(appDataStore: AppDataStore = .shared) -> [PlannerSemester] {
        let repo = appDataStore.profileRepository
        return plans(appDataStore: appDataStore).flatMap { plan in
            (try? repo.fetchSemesters(forPlanID: plan.id, limit: 200)) ?? []
        }
    }

    static func plans(collegePersistence: CollegePersistence = .shared) -> [PlannerPlan] {
        plans(appDataStore: collegePersistence.appDataStore)
    }

    static func primaryProfile(collegePersistence: CollegePersistence = .shared) -> Profile? {
        primaryProfile(appDataStore: collegePersistence.appDataStore)
    }

    static func allCoursesAcrossPlans(collegePersistence: CollegePersistence = .shared) -> [PlannerCourse] {
        allCoursesAcrossPlans(appDataStore: collegePersistence.appDataStore)
    }

    static func allSemestersAcrossPlans(collegePersistence: CollegePersistence = .shared) -> [PlannerSemester] {
        allSemestersAcrossPlans(appDataStore: collegePersistence.appDataStore)
    }
}