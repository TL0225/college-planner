// AcademicsPlannerReadBridge.swift
// Feature: Academics
// Purpose: Academics module — AcademicsPlannerReadBridge.
// Data: CollegePersistence / repositories when applicable.

import Foundation

/// local store-only planner reads for Academics (Phase 7f).
@MainActor
enum AcademicsPlannerReadBridge {
    static func semesterCourseCount(appDataStore: AppDataStore = .shared) -> Int {
        (try? appDataStore.profileRepository.totalPlannerCourseCount()) ?? 0
    }

    static func hasPlannerData(appDataStore: AppDataStore = .shared) -> Bool {
        if let plans = try? appDataStore.profileRepository.fetchPlans(limit: 1), !plans.isEmpty {
            return true
        }
        if let semesters = try? appDataStore.profileRepository.fetchSemesters(limit: 1), !semesters.isEmpty {
            return true
        }
        return false
    }
}
