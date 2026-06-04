// AcademicsPlannerCreditsBridge.swift
// Feature: Academics
// Purpose: Academics module — AcademicsPlannerCreditBuckets.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftData

/// Credit bucket totals for Academics stacked bar (local store planner).
struct AcademicsPlannerCreditBuckets: Equatable, Sendable {
    var completed: Int
    var inProgress: Int
    var planned: Int

    static let zero = AcademicsPlannerCreditBuckets(completed: 0, inProgress: 0, planned: 0)
}

@MainActor
enum AcademicsPlannerCreditsBridge {
    static func buckets(plannerSemesters: [PlannerSemester]) -> AcademicsPlannerCreditBuckets {
        buckets(from: plannerSemesters)
    }

    static func buckets(from plannerSemesters: [PlannerSemester]) -> AcademicsPlannerCreditBuckets {
        var completed = 0
        var inProgress = 0
        var planned = 0
        for semester in plannerSemesters {
            for course in semester.courses ?? [] {
                let status = course.status.trimmingCharacters(in: .whitespacesAndNewlines)
                let credits = Int(course.credits)
                if course.isCompleted || status == "Completed" {
                    completed += credits
                } else if status == "In Progress" || status == "In-Progress" {
                    inProgress += credits
                } else if status == "Planned" {
                    planned += credits
                }
            }
        }
        return AcademicsPlannerCreditBuckets(
            completed: completed,
            inProgress: inProgress,
            planned: planned
        )
    }
}
