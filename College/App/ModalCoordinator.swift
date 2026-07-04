// ModalCoordinator.swift
// Feature: App
// Purpose: App module — CourseEditSelection.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI
import Observation

/// Coordinates sheet presentation for flows that still route through a shared modal enum.
@Observable
@MainActor
final class ModalCoordinator {
    var activeModal: ActiveModal? = nil
    var courseDashboardTaskOverlay: CourseDashboardTaskOverlay? = nil
    /// Tracks whether the anchored creation panel (same UI as edit) is showing.
    /// Used by grid views to clear pending-creation range highlights when dismissed.
    var isCreationPanelOpen: Bool = false
    /// When set, the add-semester flow prefers this plan if it still exists.
    var addSemesterPreferredPlanID: UUID? = nil

    struct CourseEditSelection: Equatable {
        let courseCode: String
        let defaultCourseName: String
        let defaultCreditsText: String
    }

    /// When set, catalog picks assign to a requirement row instead of adding to a semester.
    struct RequirementCourseAssignment: Equatable {
        let universityName: String
        let programURL: String
        let requirementCategory: String
    }

    enum CourseDashboardTaskOverlay: Equatable {
        case add(semesterID: UUID?, prefillCourseID: UUID?)
        case edit(taskID: UUID)
    }

    enum ActiveModal: Equatable {
        case addSemester
        case addExperience
        case editExperience(Experience)
        case addAchievement
        case editAchievement(Achievement)
        case editCourse(CourseEditSelection)
        case addGenEdCourse
        case addCatalogCourseGlobal(tagAsGenEd: Bool)
        case addCatalogCourse(semesterID: UUID)
        case assignRequirementCourse(RequirementCourseAssignment)
        case addCalendarItem(semesterID: UUID?, initialTitle: String?, initialStart: Date?, initialEnd: Date?)
        case editCalendarItem(eventID: UUID)
        case addTask(semesterID: UUID?, prefillCourseID: UUID?)
        case editTask(taskID: UUID)
        case courseDashboard(courseCode: String, defaultCourseName: String, defaultCreditsText: String, courseID: UUID?)
        
        static func == (lhs: ActiveModal, rhs: ActiveModal) -> Bool {
            switch (lhs, rhs) {
            case (.addSemester, .addSemester):
                return true
            case (.addExperience, .addExperience):
                return true
            case (.editExperience(let a), .editExperience(let b)):
                return a.id == b.id
            case (.addAchievement, .addAchievement):
                return true
            case (.editAchievement(let a), .editAchievement(let b)):
                return a.id == b.id
            case (.editCourse(let a), .editCourse(let b)):
                return a.courseCode == b.courseCode
            case (.addGenEdCourse, .addGenEdCourse):
                return true
            case (.addCatalogCourseGlobal(let a), .addCatalogCourseGlobal(let b)):
                return a == b
            case (.addCatalogCourse(let aID), .addCatalogCourse(let bID)):
                return aID == bID
            case (.assignRequirementCourse(let a), .assignRequirementCourse(let b)):
                return a == b
            case (.addCalendarItem(let aSemester, let aTitle, let aStart, let aEnd), .addCalendarItem(let bSemester, let bTitle, let bStart, let bEnd)):
                return aSemester == bSemester && aTitle == bTitle && aStart == bStart && aEnd == bEnd
            case (.editCalendarItem(let aID), .editCalendarItem(let bID)):
                return aID == bID
            case (.addTask(let aSemester, let aCourse), .addTask(let bSemester, let bCourse)):
                return aSemester == bSemester && aCourse == bCourse
            case (.editTask(let aID), .editTask(let bID)):
                return aID == bID
            case (.courseDashboard(let aCode, let aName, let aCredits, let aCourseID), .courseDashboard(let bCode, let bName, let bCredits, let bCourseID)):
                return aCode == bCode && aName == bName && aCredits == bCredits && aCourseID == bCourseID
            default:
                return false
            }
        }
    }
}
