import SwiftUI
import Combine
import CoreData

/// Simple app-wide modal coordinator so overlays can be presented above page content
/// (like AddCourseView) without being clipped by nested cards.
@MainActor
final class ModalCoordinator: ObservableObject {
    @Published var activeModal: ActiveModal? = nil
    @Published var courseDashboardTaskOverlay: CourseDashboardTaskOverlay? = nil
    /// Tracks whether the anchored creation panel (same UI as edit) is showing.
    /// Used by grid views to clear pending-creation range highlights when dismissed.
    @Published var isCreationPanelOpen: Bool = false

    struct CourseEditSelection: Equatable {
        let courseCode: String
        let defaultCourseName: String
        let defaultCreditsText: String
    }

    enum CourseDashboardTaskOverlay: Equatable {
        case add(semesterID: UUID?, prefillCourseObjectID: NSManagedObjectID?)
        case edit(objectID: NSManagedObjectID)
    }

    enum ActiveModal: Equatable {
        case addSemester
        case addExperience
        case editExperience(ExperienceEntity)
        case addAchievement
        case editAchievement(AchievementEntity)
        case editCourse(CourseEditSelection)
        case addGenEdCourse
        case addCatalogCourseGlobal(tagAsGenEd: Bool)
        case addCatalogCourse(semesterObjectID: NSManagedObjectID)
        case addCalendarItem(semesterID: UUID?, initialTitle: String?, initialStart: Date?, initialEnd: Date?)
        case editCalendarItem(objectID: NSManagedObjectID)
        case addTask(semesterID: UUID?, prefillCourseObjectID: NSManagedObjectID?)
        case editTask(objectID: NSManagedObjectID)
        case courseDashboard(courseCode: String, defaultCourseName: String, defaultCreditsText: String, courseObjectID: NSManagedObjectID?)
        
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
            case (.addCalendarItem(let aSemester, let aTitle, let aStart, let aEnd), .addCalendarItem(let bSemester, let bTitle, let bStart, let bEnd)):
                return aSemester == bSemester && aTitle == bTitle && aStart == bStart && aEnd == bEnd
            case (.editCalendarItem(let aID), .editCalendarItem(let bID)):
                return aID == bID
            case (.addTask(let aSemester, let aCourse), .addTask(let bSemester, let bCourse)):
                return aSemester == bSemester && aCourse == bCourse
            case (.editTask(let aID), .editTask(let bID)):
                return aID == bID
            case (.courseDashboard(let aCode, let aName, let aCredits, let aObjectID), .courseDashboard(let bCode, let bName, let bCredits, let bObjectID)):
                return aCode == bCode && aName == bName && aCredits == bCredits && aObjectID == bObjectID
            default:
                return false
            }
        }
    }
}
