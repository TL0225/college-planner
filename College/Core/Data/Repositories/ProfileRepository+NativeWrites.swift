// ProfileRepository+NativeWrites.swift
// Feature: Core/Data
// Purpose: Core/Data persistence — — ProfileRepository+NativeWrites.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftData

extension ProfileRepository {
    @discardableResult
    func createPlan(
        name: String,
        type: String,
        major: String,
        minor: String,
        concentration: String
    ) throws -> PlannerPlan {
        let plan = PlannerPlan(
            name: name,
            type: type,
            major: major.isEmpty ? nil : major,
            minor: minor.isEmpty ? nil : minor,
            concentration: concentration.isEmpty ? nil : concentration
        )
        context.insert(plan)
        try context.save()
        return plan
    }

    @discardableResult
    func createSemester(
        plan: PlannerPlan,
        name: String,
        year: Int,
        season: String,
        seasonOrder: Int16
    ) throws -> PlannerSemester {
        let semester = PlannerSemester(
            name: name,
            year: Int16(year),
            season: season,
            seasonOrder: seasonOrder
        )
        semester.plan = plan
        context.insert(semester)
        try context.save()
        return semester
    }

    func seasonOrder(for season: String) -> Int16 {
        switch season.lowercased() {
        case "spring": return 0
        case "summer": return 1
        case "fall": return 2
        case "winter": return 3
        default: return 0
        }
    }
}