import Foundation
import SwiftUI

public enum CalendarToolbarAction: Sendable, Equatable {
    case previous
    case next
    case modeChange(CalendarViewDisplayMode)
    case sidebarToggle
    case sidebarPanelChange(CalendarSidebarPanel)
}

@MainActor
public protocol CalendarToolbarHandlerToken: AnyObject {
    func invalidate()
}

@MainActor
public protocol CalendarToolbarDispatching: AnyObject {
    func registerCalendarHandler(_ handler: @escaping (CalendarToolbarAction) -> Void) -> CalendarToolbarHandlerToken
}

@MainActor
public enum CalendarToolbarAccess {
    public static weak var dispatcher: (any CalendarToolbarDispatching)?
}

public enum CalendarNotificationStyle: Sendable {
    case info
    case warning
    case error
    case success
    case progress
}

@MainActor
public protocol CalendarNotificationPosting: AnyObject {
    @discardableResult
    func post(
        kind: CalendarNotificationStyle,
        title: String,
        message: String,
        progress: Double?,
        autoDismissAfter: TimeInterval?
    ) -> UUID

    func update(
        id: UUID,
        title: String?,
        message: String?,
        kind: CalendarNotificationStyle?,
        progress: Double?,
        autoDismissAfter: TimeInterval?
    )

    func complete(
        id: UUID,
        kind: CalendarNotificationStyle,
        title: String?,
        message: String?,
        autoDismissAfter: TimeInterval?
    )
}

@MainActor
public enum CalendarNotificationAccess {
    public static weak var notifications: (any CalendarNotificationPosting)?
}

@MainActor
public protocol CalendarModalCoordinating: AnyObject {
    var isAddCalendarItemPresented: Bool { get set }
    var isEditCalendarItemPresented: Bool { get set }
    var addCalendarItemSemesterID: UUID? { get }
    var addCalendarItemInitialTitle: String? { get }
    var addCalendarItemInitialStart: Date? { get }
    var addCalendarItemInitialEnd: Date? { get }
    var editCalendarItemID: UUID? { get }
    func presentAddCalendarItem(semesterID: UUID?, title: String?, start: Date?, end: Date?)
    func presentEditCalendarItem(eventID: UUID)
    func presentAddTask(semesterID: UUID?, prefillCourseID: UUID?)
    func presentAddCatalogCourse(semesterID: UUID)
    func dismissActiveModalIfCalendar()
}

@MainActor
public enum CalendarModalAccess {
    public static weak var coordinator: (any CalendarModalCoordinating)?
}

private struct CalendarModalEnvironmentKey: EnvironmentKey {
    nonisolated(unsafe) static let defaultValue: (any CalendarModalCoordinating)? = nil
}

public extension EnvironmentValues {
    var calendarModalCoordinator: (any CalendarModalCoordinating)? {
        get { self[CalendarModalEnvironmentKey.self] }
        set { self[CalendarModalEnvironmentKey.self] = newValue }
    }
}
