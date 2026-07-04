import CollegeCalendar
import Foundation
import SwiftUI

@MainActor
final class AppNotificationCenterCalendarAdapter: CalendarNotificationPosting {
    private let center: AppNotificationCenter

    init(center: AppNotificationCenter) {
        self.center = center
    }

    func post(
        kind: CalendarNotificationStyle,
        title: String,
        message: String,
        progress: Double?,
        autoDismissAfter: TimeInterval?
    ) -> UUID {
        center.post(
            kind: map(kind),
            title: title,
            message: message,
            progress: progress,
            autoDismissAfter: autoDismissAfter
        )
    }

    func update(
        id: UUID,
        title: String?,
        message: String?,
        kind: CalendarNotificationStyle?,
        progress: Double?,
        autoDismissAfter: TimeInterval?
    ) {
        center.update(
            id: id,
            title: title,
            message: message,
            kind: kind.map(map),
            progress: progress,
            autoDismissAfter: autoDismissAfter
        )
    }

    func complete(
        id: UUID,
        kind: CalendarNotificationStyle,
        title: String?,
        message: String?,
        autoDismissAfter: TimeInterval?
    ) {
        center.complete(
            id: id,
            kind: map(kind),
            title: title,
            message: message,
            autoDismissAfter: autoDismissAfter ?? 4
        )
    }

    private func map(_ style: CalendarNotificationStyle) -> AppNotificationCenter.AppNotification.Kind {
        switch style {
        case .info: .info
        case .warning: .warning
        case .error: .error
        case .success: .success
        case .progress: .progress
        }
    }
}

@MainActor
final class ModalCoordinatorCalendarAdapter: CalendarModalCoordinating {
    private let coordinator: ModalCoordinator

    init(coordinator: ModalCoordinator) {
        self.coordinator = coordinator
    }

    var isAddCalendarItemPresented: Bool {
        get {
            if case .addCalendarItem = coordinator.activeModal { return true }
            return false
        }
        set {
            if !newValue, case .addCalendarItem = coordinator.activeModal {
                coordinator.activeModal = nil
            }
        }
    }

    var isEditCalendarItemPresented: Bool {
        get {
            if case .editCalendarItem = coordinator.activeModal { return true }
            return false
        }
        set {
            if !newValue, case .editCalendarItem = coordinator.activeModal {
                coordinator.activeModal = nil
            }
        }
    }

    var addCalendarItemSemesterID: UUID? {
        guard case .addCalendarItem(let semesterID, _, _, _) = coordinator.activeModal else { return nil }
        return semesterID
    }

    var addCalendarItemInitialTitle: String? {
        guard case .addCalendarItem(_, let title, _, _) = coordinator.activeModal else { return nil }
        return title
    }

    var addCalendarItemInitialStart: Date? {
        guard case .addCalendarItem(_, _, let start, _) = coordinator.activeModal else { return nil }
        return start
    }

    var addCalendarItemInitialEnd: Date? {
        guard case .addCalendarItem(_, _, _, let end) = coordinator.activeModal else { return nil }
        return end
    }

    var editCalendarItemID: UUID? {
        guard case .editCalendarItem(let eventID) = coordinator.activeModal else { return nil }
        return eventID
    }

    func presentAddCalendarItem(semesterID: UUID?, title: String?, start: Date?, end: Date?) {
        coordinator.activeModal = .addCalendarItem(
            semesterID: semesterID,
            initialTitle: title,
            initialStart: start,
            initialEnd: end
        )
    }

    func presentEditCalendarItem(eventID: UUID) {
        coordinator.activeModal = .editCalendarItem(eventID: eventID)
    }

    func presentAddTask(semesterID: UUID?, prefillCourseID: UUID?) {
        coordinator.activeModal = .addTask(semesterID: semesterID, prefillCourseID: prefillCourseID)
    }

    func presentAddCatalogCourse(semesterID: UUID) {
        coordinator.activeModal = .addCatalogCourse(semesterID: semesterID)
    }

    func dismissActiveModalIfCalendar() {
        switch coordinator.activeModal {
        case .addCalendarItem, .editCalendarItem, .addTask:
            coordinator.activeModal = nil
        default:
            break
        }
    }
}

@MainActor
final class ToolbarDispatcherCalendarAdapter: CalendarToolbarDispatching {
    private let dispatcher: ToolbarDispatcher
    init(dispatcher: ToolbarDispatcher) { self.dispatcher = dispatcher }

    func registerCalendarHandler(_ handler: @escaping (CalendarToolbarAction) -> Void) -> CalendarToolbarHandlerToken {
        let token = dispatcher.register(owner: .calendar) { action in
            guard case .calendar(let calendarAction) = action else { return }
            handler(calendarAction)
        }
        return ToolbarHandlerTokenBox(token)
    }
}

@MainActor
private final class ToolbarHandlerTokenBox: CalendarToolbarHandlerToken {
    private let token: ToolbarHandlerToken
    init(_ token: ToolbarHandlerToken) { self.token = token }
    func invalidate() { token.invalidate() }
}

@MainActor
final class CalendarShellPortAdapters {
    let notifications: AppNotificationCenterCalendarAdapter
    let modalCoordinator: ModalCoordinatorCalendarAdapter
    let toolbarDispatcher: ToolbarDispatcherCalendarAdapter

    init(
        appNotifications: AppNotificationCenter,
        modalCoordinator: ModalCoordinator,
        toolbarDispatcher: ToolbarDispatcher
    ) {
        notifications = AppNotificationCenterCalendarAdapter(center: appNotifications)
        self.modalCoordinator = ModalCoordinatorCalendarAdapter(coordinator: modalCoordinator)
        self.toolbarDispatcher = ToolbarDispatcherCalendarAdapter(dispatcher: toolbarDispatcher)
    }
}

extension CalendarPersistencePortBootstrap {
    @MainActor
    static func wireShell(container: AppContainer) {
        CalendarNotificationAccess.notifications = container.calendarShellPorts.notifications
        CalendarModalAccess.coordinator = container.calendarShellPorts.modalCoordinator
        CalendarToolbarAccess.dispatcher = container.calendarShellPorts.toolbarDispatcher
        CalendarIntegrationBridge.manager = container.calendarManager
        CalendarProviderSyncBridge.wireIntegrationBridge()
    }
}
