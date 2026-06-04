// PlannerStoreAccessors.swift
// Feature: Core/Data
// Purpose: Core/Data persistence — — PlannerStoreAccessors.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftData

extension PlannerSemester {
    var coursesArray: [PlannerCourse] {
        let list = courses ?? []
        return list.sorted {
            if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
            return $0.code.localizedCaseInsensitiveCompare($1.code) == .orderedAscending
        }
    }

    var totalCredits: Int {
        coursesArray
            .filter { course in
                let status = course.status.trimmingCharacters(in: .whitespacesAndNewlines)
                return status != "Dropped" && status != "Not Planned" && status != "Failed"
            }
            .reduce(0) { $0 + Int($1.credits) }
    }

    var progress: Double {
        let total = totalCredits
        guard total > 0 else { return 0 }
        let completed = coursesArray
            .filter(\.isCompleted)
            .reduce(0) { $0 + Int($1.credits) }
        return Double(completed) / Double(total)
    }
}

extension PlannerPlan {
    var semestersArray: [PlannerSemester] {
        let list = semesters ?? []
        return list.sorted {
            if $0.year != $1.year { return $0.year < $1.year }
            return $0.seasonOrder < $1.seasonOrder
        }
    }
}

extension PlannerCourse {
    var creditsInt: Int { Int(credits) }
}

extension Profile {
    var experiencesArray: [Experience] {
        (experiences ?? []).sorted { ($0.startDate ?? .distantPast) > ($1.startDate ?? .distantPast) }
    }

    var achievementsArray: [Achievement] {
        (achievements ?? []).sorted { ($0.dateReceived ?? .distantPast) > ($1.dateReceived ?? .distantPast) }
    }
}