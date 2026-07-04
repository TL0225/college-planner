// CalendarEventEditorSheet.swift
// Feature: Calendar
// Purpose: Calendar module — CalendarEventEditorSheet.
// Data: CollegePersistence / repositories when applicable.

import CollegeCalendar
import SwiftUI

/// Centered macOS sheet content for add/edit calendar events (`ModalCoordinator` cases).
struct CalendarEventEditorSheet: View {
    @Environment(AppContainer.self) private var container
    private var persistence: CollegePersistence { container.persistence }
    private var modalCoordinator: ModalCoordinator { container.modalCoordinator }
    private var collegePersistence: CollegePersistence { container.persistence }
    @StateObject private var editorSession = CalendarEditorSession()
    var zoomSourceID: String = "calendarEditorSheet"
    var zoomNamespace: Namespace.ID

    private var dismissBinding: Binding<Bool> {
        Binding(
            get: { modalCoordinator.activeModal != nil },
            set: { isPresented in
                if !isPresented { modalCoordinator.activeModal = nil }
            }
        )
    }

    var body: some View {
        Group {
            switch modalCoordinator.activeModal {
            case .addCalendarItem(let semesterID, let title, let start, let end):
                AddCalendarItemOverlay(
                    isPresented: dismissBinding,
                    semester: semesterID.flatMap { collegePersistence.semester(with: $0) },
                    initialTitle: title,
                    initialStartDateTime: start,
                    initialEndDateTime: end,
                    eventToEdit: nil,
                    presentationStyle: .anchoredPanel,
                    onLiveUpdate: { _, _, _, _ in collegePersistence.notifyCalendarDidChange() }
                )

            case .editCalendarItem(let eventID):
                let event = collegePersistence.calendarEventEntity(id: eventID)
                AddCalendarItemOverlay(
                    isPresented: dismissBinding,
                    semester: event?.semester,
                    initialTitle: nil,
                    initialStartDateTime: event?.startDate,
                    initialEndDateTime: event?.endDate,
                    eventToEdit: event,
                    presentationStyle: .anchoredPanel,
                    onLiveUpdate: { _, _, _, _ in collegePersistence.notifyCalendarDidChange() }
                )

            default:
                EmptyView()
            }
        }
        .calendarEditorPresentation(.sidebarSheet)
        .frame(minWidth: 480, idealWidth: 520, maxWidth: 640)
        .frame(minHeight: 560, idealHeight: 640, maxHeight: 720)
        .matchedTransitionSource(id: zoomSourceID, in: zoomNamespace)
    }
}
