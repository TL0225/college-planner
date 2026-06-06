// CalendarModalHost.swift
// Feature: Calendar
// Purpose: Calendar module — CalendarModalHost.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI

/// Global floating modal host for calendar events and tasks (unified Tahoe-style overlay).
struct CalendarModalHost: View {
    @Environment(AppContainer.self) private var container
    private var persistence: CollegePersistence { container.persistence }
    private var modalCoordinator: ModalCoordinator { container.modalCoordinator }
    private var collegePersistence: CollegePersistence { container.persistence }
    var body: some View {
        ZStack {
            switch modalCoordinator.activeModal {
            case .addCalendarItem, .editCalendarItem:
                EmptyView()

            case .addTask(let semesterID, let prefillCourseID):
                floatingTaskOverlay(
                    isPresented: dismissBinding,
                    semesterID: semesterID,
                    prefillCourseID: prefillCourseID,
                    taskToEdit: nil
                )

            case .editTask(let taskID):
                let task = try? collegePersistence.calendarRepository.fetchPlannerTask(id: taskID)
                floatingTaskOverlay(
                    isPresented: dismissBinding,
                    semesterID: task?.semester?.id,
                    prefillCourseID: task?.course?.id,
                    taskToEdit: task
                )

            default:
                EmptyView()
            }
        }
        .allowsHitTesting(calendarModalHostHandlesHitTesting)
    }

    private var calendarModalHostHandlesHitTesting: Bool {
        guard let modal = modalCoordinator.activeModal else { return false }
        switch modal {
        case .addCalendarItem, .editCalendarItem:
            return false
        default:
            return true
        }
    }

    private var dismissBinding: Binding<Bool> {
        Binding(
            get: { modalCoordinator.activeModal != nil },
            set: { isPresented in
                if !isPresented { modalCoordinator.activeModal = nil }
            }
        )
    }

    @ViewBuilder
    private func floatingEventOverlay(
        isPresented: Binding<Bool>,
        semesterID: UUID?,
        initialTitle: String?,
        initialStart: Date?,
        initialEnd: Date?,
        eventToEdit: CalendarEvent?
    ) -> some View {
        AddCalendarItemOverlay(
            isPresented: isPresented,
            semester: semesterID.flatMap { collegePersistence.semester(with: $0) },
            initialTitle: initialTitle,
            initialStartDateTime: initialStart,
            initialEndDateTime: initialEnd,
            eventToEdit: eventToEdit,
            presentationStyle: .floatingCards
        )
        .transition(.opacity.combined(with: .scale(scale: 0.985)))
        .zIndex(300)
    }

    @ViewBuilder
    private func floatingTaskOverlay(
        isPresented: Binding<Bool>,
        semesterID: UUID?,
        prefillCourseID: UUID?,
        taskToEdit: PlannerTask?
    ) -> some View {
        let repo = collegePersistence.profileRepository
        let prefillCourse = prefillCourseID.flatMap { try? repo.fetchCourse(id: $0) }
        let semesterFromID = semesterID.flatMap { collegePersistence.semester(with: $0) }
        let effectiveSemester = semesterFromID ?? prefillCourse?.semester

        AddTaskOverlay(
            isPresented: isPresented,
            semester: effectiveSemester,
            taskToEdit: taskToEdit,
            prefillCourseID: prefillCourseID,
            presentationStyle: .fullScreenOverlay
        )
        .transition(.opacity.combined(with: .scale(scale: 0.985)))
        .zIndex(300)
    }
}
