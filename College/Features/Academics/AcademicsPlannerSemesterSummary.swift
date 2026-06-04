// AcademicsPlannerSemesterSummary.swift
// Feature: Academics
// Purpose: Academics module — AcademicsPlannerSemesterSummary.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftData

/// Presentation model for planner semester rows; backed by local store.
struct AcademicsPlannerSemesterSummary: Identifiable, Equatable, Sendable {
    let id: UUID
    let season: String
    let year: Int
    let name: String
    let totalCredits: Int
    let courseCount: Int
    let dominantState: AcademicsStatusPalette.State

    var displayTitle: String {
        let trimmedSeason = season.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedSeason.isEmpty { return "Semester \(year)" }
        return "\(trimmedSeason) \(year)"
    }

    init(planner semester: PlannerSemester) {
        id = semester.id
        season = semester.season
        year = Int(semester.year)
        name = semester.name
        let courses = semester.courses ?? []
        courseCount = courses.count
        totalCredits = Self.totalCredits(from: courses.map { ($0.status, Int($0.credits), $0.isCompleted) })
        dominantState = Self.dominantState(from: courses.map { ($0.status, $0.isCompleted) })
    }

    private static func totalCredits(from courses: [(status: String, credits: Int, isCompleted: Bool)]) -> Int {
        courses.reduce(0) { partial, course in
            let status = course.status.trimmingCharacters(in: .whitespacesAndNewlines)
            guard status != "Dropped", status != "Not Planned", status != "Failed" else { return partial }
            return partial + course.credits
        }
    }

    private static func dominantState(from courses: [(status: String, isCompleted: Bool)]) -> AcademicsStatusPalette.State {
        if courses.isEmpty { return .planned }
        if courses.allSatisfy(\.isCompleted) { return .completed }
        if courses.contains(where: {
            let status = $0.status.trimmingCharacters(in: .whitespacesAndNewlines)
            return status == "In Progress" || status == "In-Progress"
        }) {
            return .inProgress
        }
        if courses.contains(where: \.isCompleted) { return .inProgress }
        return .planned
    }
}

@MainActor
enum AcademicsPlannerSemesterBridge {
    static func summaries(semesters: [PlannerSemester]) -> [AcademicsPlannerSemesterSummary] {
        semesters.map(AcademicsPlannerSemesterSummary.init(planner:))
    }

    static func resolvePlannerSemester(id: UUID, appDataStore: AppDataStore = .shared) -> PlannerSemester? {
        try? appDataStore.profileRepository.fetchSemester(id: id)
    }
}
