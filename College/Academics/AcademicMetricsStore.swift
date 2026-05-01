import Combine
import CoreData
import Foundation
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

    static func resolveCurrentSemester(from semesters: [SemesterEntity], date: Date = Date()) -> SemesterEntity? {
        guard !semesters.isEmpty else { return nil }

        let now = currentSeasonYear(date: date)

        let exactMatches = semesters.filter { semester in
            let semSeason = normalizedSeason(semester.season ?? "")
            return semSeason == now.season && Int(semester.year) == now.year
        }

        if let exact = exactMatches.sorted(by: { lhs, rhs in
            if lhs.isPlanned != rhs.isPlanned { return !lhs.isPlanned }
            if lhs.coursesArray.count != rhs.coursesArray.count { return lhs.coursesArray.count > rhs.coursesArray.count }
            return (lhs.name ?? "") < (rhs.name ?? "")
        }).first {
            return exact
        }

        let nowKey = semesterKey(year: now.year, season: now.season)
        return semesters.min { lhs, rhs in
            let lhsSeason = normalizedSeason(lhs.season ?? "")
            let rhsSeason = normalizedSeason(rhs.season ?? "")
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
/// GPA rules match `GPACalculatorPopoverView` + `CoreDataManager.isLetterGradedForGPA`.
@MainActor
final class AcademicMetricsStore: ObservableObject {
    @Published private(set) var snapshot: AcademicMetricsSnapshot?

    private let coreData: CoreDataManager
    private lazy var gradeScaleStore = GPAGradeScaleStore(universityID: nil)

    init(coreData: CoreDataManager = .shared) {
        self.coreData = coreData
    }

    func refresh() {
        let mapping = gradeScaleStore.gradePointsMapping
        let plan = coreData.getActivePlan()
        let semesters = plan?.semestersArray ?? []
        let sortedSemesters = semesters

        let gpaResult = GPACalculation.cumulativeGPA(
            semesters: sortedSemesters,
            mapping: mapping,
            isLetterGradedForGPA: { course in
                coreData.isLetterGradedForGPA(course.gradingType ?? "")
            }
        )

        let completedCredits = Self.totalCompletedCredits(semesters: sortedSemesters)
        let profile = coreData.profile
        let required = max(0, Int(profile?.creditsRequired ?? 120))

        let currentSemester = AcademicTermResolver.resolveCurrentSemester(from: sortedSemesters) ?? sortedSemesters.last
        let termLabel = currentSemester.map(Self.semesterDisplayName)
        let termProgress = currentSemester?.progress ?? 0
        let termCourses: [AcademicTermCourseRow] = (currentSemester?.coursesArray ?? []).compactMap { course in
            guard let cid = course.id else { return nil }
            return AcademicTermCourseRow(
                id: cid,
                code: (course.code ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                name: (course.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                credits: course.creditsInt,
                isCompleted: course.isCompleted,
                syllabusFileName: course.syllabusFileName,
                professor: (course.professor ?? "").trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                officeHours: (course.professorOfficeHours ?? "").trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
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

    private static func totalCompletedCredits(semesters: [SemesterEntity]) -> Int {
        var total = 0
        for semester in semesters {
            for course in semester.coursesArray where course.isCompleted {
                total += course.creditsInt
            }
        }
        return total
    }

    private static func semesterDisplayName(_ semester: SemesterEntity) -> String {
        let season = (semester.season ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let year = Int(semester.year)
        if season.isEmpty { return semester.name ?? "Semester" }
        if year > 0 { return "\(season) \(year)" }
        return season
    }
}

struct AcademicMetricsSnapshot: Equatable {
    /// Cumulative GPA from completed, letter-graded courses in the active plan; nil when none qualify.
    var cumulativeGPA: Double?
    var gpaCreditsCounted: Double
    var gpaCoursesCounted: Int
    /// Sum of credit hours for all completed courses (includes non–letter-graded completions).
    var completedCreditsTotal: Int
    var creditsRequired: Int
    var currentSemesterLabel: String?
    /// Semester-level completion ratio (completed credits / planned credits) for the resolved current term.
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
