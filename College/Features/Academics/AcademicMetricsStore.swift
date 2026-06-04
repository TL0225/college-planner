// AcademicMetricsStore.swift
// Feature: Academics
// Purpose: Academics module — AcademicMetricsSnapshot.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import Observation
import SwiftUI

private extension String {
    var nilIfEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}

enum AcademicTermResolver {
    private static func normalizedSeason(_ value: String) -> String {
        let s = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if s.contains("spring") { return "spring" }
        if s.contains("summer") { return "summer" }
        if s.contains("fall") || s.contains("autumn") { return "fall" }
        if s.contains("winter") { return "winter" }
        return s
    }

    private static func seasonOrder(for normalizedSeason: String) -> Int {
        switch normalizedSeason {
        case "fall": return 0
        case "winter": return 1
        case "spring": return 2
        case "summer": return 3
        default: return 4
        }
    }

    private static func currentSeasonYear(date: Date = Date(), calendar: Calendar = .current) -> (season: String, year: Int) {
        let month = calendar.component(.month, from: date)
        let year = calendar.component(.year, from: date)
        switch month {
        case 3...5:
            return ("spring", year)
        case 6...8:
            return ("summer", year)
        case 9...11:
            return ("fall", year)
        default:
            return ("winter", year)
        }
    }

    private static func semesterKey(year: Int, season: String) -> Int {
        (year * 10) + seasonOrder(for: season)
    }

    static func resolveCurrentSemester(from semesters: [PlannerSemester], date: Date = Date()) -> PlannerSemester? {
        guard !semesters.isEmpty else { return nil }

        let now = currentSeasonYear(date: date)

        let exactMatches = semesters.filter { semester in
            let semSeason = normalizedSeason(semester.season)
            return semSeason == now.season && Int(semester.year) == now.year
        }

        if let exact = exactMatches.sorted(by: { lhs, rhs in
            if lhs.isPlanned != rhs.isPlanned { return !lhs.isPlanned }
            if lhs.coursesArray.count != rhs.coursesArray.count { return lhs.coursesArray.count > rhs.coursesArray.count }
            return lhs.name < rhs.name
        }).first {
            return exact
        }

        let nowKey = semesterKey(year: now.year, season: now.season)
        return semesters.min { lhs, rhs in
            let lhsSeason = normalizedSeason(lhs.season)
            let rhsSeason = normalizedSeason(rhs.season)
            let lhsKey = semesterKey(year: Int(lhs.year), season: lhsSeason)
            let rhsKey = semesterKey(year: Int(rhs.year), season: rhsSeason)

            let lhsDistance = abs(lhsKey - nowKey)
            let rhsDistance = abs(rhsKey - nowKey)
            if lhsDistance != rhsDistance { return lhsDistance < rhsDistance }

            if lhs.isPlanned != rhs.isPlanned { return !lhs.isPlanned }
            if lhs.coursesArray.count != rhs.coursesArray.count { return lhs.coursesArray.count > rhs.coursesArray.count }
            return lhsKey > rhsKey
        }
    }
}

/// Shared, planner-derived academic metrics (GPA, credits, current term) for Overview, Profile, and Academics.
@Observable
@MainActor
final class AcademicMetricsStore {
    private(set) var snapshot: AcademicMetricsSnapshot?

    private let collegePersistence: CollegePersistence
    private let gradeScaleStore: GPAGradeScaleStore

    init(collegePersistence: CollegePersistence = .shared) {
        self.collegePersistence = collegePersistence
        self.gradeScaleStore = GPAGradeScaleStore(universityID: nil)
    }

    func refresh() {
        let mapping = gradeScaleStore.gradePointsMapping
        let plan = collegePersistence.getActivePlan()
        let sortedSemesters = plan?.semestersArray ?? collegePersistence.semesters

        let gpaResult = GPACalculation.cumulativeGPA(
            semesters: sortedSemesters,
            mapping: mapping,
            isLetterGradedForGPA: { course in
                collegePersistence.isLetterGradedForGPA(course.gradingType.isEmpty ? nil : course.gradingType)
            }
        )

        let completedCredits = Self.totalCompletedCredits(semesters: sortedSemesters)
        let required = Self.resolveCreditsRequired(collegePersistence: collegePersistence)

        let currentSemester = AcademicTermResolver.resolveCurrentSemester(from: sortedSemesters) ?? sortedSemesters.last
        let termLabel = currentSemester.map(Self.semesterDisplayName)
        let termProgress = currentSemester?.progress ?? 0
        let termCourses: [AcademicTermCourseRow] = (currentSemester?.coursesArray ?? []).map { course in
            AcademicTermCourseRow(
                id: course.id,
                code: course.code.trimmingCharacters(in: .whitespacesAndNewlines),
                name: course.name.trimmingCharacters(in: .whitespacesAndNewlines),
                credits: course.creditsInt,
                isCompleted: course.isCompleted,
                syllabusFileName: nil,
                professor: course.professor?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                officeHours: nil
            )
        }

        snapshot = AcademicMetricsSnapshot(
            cumulativeGPA: gpaResult?.gpa,
            gpaCreditsCounted: Double(gpaResult?.creditsCounted ?? 0),
            gpaCoursesCounted: gpaResult?.coursesCounted ?? 0,
            completedCreditsTotal: completedCredits,
            creditsRequired: required,
            currentSemesterLabel: termLabel,
            currentTermProgress: termProgress,
            currentTermCourses: termCourses
        )
    }

    private static func totalCompletedCredits(semesters: [PlannerSemester]) -> Int {
        var total = 0
        for semester in semesters {
            for course in semester.coursesArray where course.isCompleted {
                total += course.creditsInt
            }
        }
        return total
    }

    private static func resolveCreditsRequired(collegePersistence: CollegePersistence) -> Int {
        let primaryRequired = collegePersistence.declaredProgramsCreditsBreakdown().primary.requiredRoundedInt
        if primaryRequired > 0 { return primaryRequired }

        if let primary = collegePersistence.primaryAcademicProfile,
           let storedRequired = primary.creditsRequired,
           storedRequired > 0 {
            let stored = Int(storedRequired)
            let majors = collegePersistence.resolvedMajorNames()
            if stored == 120,
               let inferred = DeclaredProgramDegreeMetadata.infer(fromProgramDisplays: majors),
               !DegreeConfiguration.isUndergraduate(inferred.degreeLevel) {
                return 0
            }
            return stored
        }

        return 0
    }

    private static func semesterDisplayName(_ semester: PlannerSemester) -> String {
        let season = semester.season.trimmingCharacters(in: .whitespacesAndNewlines)
        let year = Int(semester.year)
        if season.isEmpty { return semester.name }
        if year > 0 { return "\(season) \(year)" }
        return season
    }
}

struct AcademicMetricsSnapshot: Equatable {
    var cumulativeGPA: Double?
    var gpaCreditsCounted: Double
    var gpaCoursesCounted: Int
    var completedCreditsTotal: Int
    var creditsRequired: Int
    var currentSemesterLabel: String?
    var currentTermProgress: Double
    var currentTermCourses: [AcademicTermCourseRow]
}

struct AcademicTermCourseRow: Identifiable, Equatable {
    let id: UUID
    let code: String
    let name: String
    let credits: Int
    let isCompleted: Bool
    let syllabusFileName: String?
    let professor: String?
    let officeHours: String?
}
