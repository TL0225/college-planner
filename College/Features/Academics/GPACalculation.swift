// GPACalculation.swift
// Feature: Academics
// Purpose: Academics module — GPACalculationResult.
// Data: CollegePersistence / repositories when applicable.

import Foundation

struct GPACalculationResult {
    let gpa: Double
    let creditsCounted: Int
    let coursesCounted: Int
}

enum GPACalculation {
    static func cumulativeGPA(
        semesters: [PlannerSemester],
        mapping: [String: Double],
        isLetterGradedForGPA: (PlannerCourse) -> Bool
    ) -> GPACalculationResult? {
        var qualityPoints = 0.0
        var credits = 0
        var courses = 0

        for semester in semesters {
            for course in semester.coursesArray where course.isCompleted {
                guard isLetterGradedForGPA(course) else { continue }
                let grade = (course.grade ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                guard let points = mapping[grade] else { continue }
                let c = max(0, Int(course.credits))
                guard c > 0 else { continue }
                qualityPoints += points * Double(c)
                credits += c
                courses += 1
            }
        }

        guard credits > 0 else { return nil }
        return GPACalculationResult(gpa: qualityPoints / Double(credits), creditsCounted: credits, coursesCounted: courses)
    }
}
