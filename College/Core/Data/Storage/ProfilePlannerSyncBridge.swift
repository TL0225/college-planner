// ProfilePlannerSyncBridge.swift
// Feature: Core/Data
// Purpose: Core/Data persistence — — ProfilePlannerSyncBridge.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftData

/// Test hooks for planner query-host refresh (Phase 1A).
@MainActor
enum ProfilePlannerSyncBridge {
    static func resetSyncTokenForTesting() {}
}

extension ProfileRepository {
    func totalPlannerCourseCount() throws -> Int {
        try context.fetchCount(FetchDescriptor<PlannerCourse>())
    }
}