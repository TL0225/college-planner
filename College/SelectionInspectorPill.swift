import SwiftUI
import CoreData

struct SelectionInspectorPill: View {
    @EnvironmentObject private var coreDataManager: CoreDataManager
    @EnvironmentObject private var modalCoordinator: ModalCoordinator
    @EnvironmentObject private var pillCoordinator: PillCoordinator
    @EnvironmentObject private var calendarManager: CalendarIntegrationManager

    let selection: PillCoordinator.Selection
    @Binding var activePage: AppPage

    var showsCalendarButton: Bool = true

    @State private var title: String = ""
    @State private var subtitle: String = ""
    @State private var resolvedObjectID: NSManagedObjectID? = nil
    @State private var resolvedSemesterID: UUID? = nil

    var body: some View {
        HStack(spacing: 12) {
            Button {
                pillCoordinator.clearSelection()
            } label: {
                Image(systemName: "xmark")
                    .font(DesignSystem.Fonts.main(size: 13, weight: .bold))
                    .foregroundColor(DesignSystem.Colors.textMain)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.black.opacity(0.04)))
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityLabel("Close")

            VStack(alignment: .leading, spacing: 2) {
                Text(title.isEmpty ? "Selected" : title)
                    .font(DesignSystem.Fonts.main(size: 13, weight: .bold))
                    .foregroundColor(DesignSystem.Colors.textMain)
                    .lineLimit(1)

                Text(subtitle)
                    .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.textLight)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if showsCalendarButton && activePage != .calendar {
                Button {
                    activePage = .calendar
                } label: {
                    Image(systemName: AppPage.calendar.icon)
                        .font(DesignSystem.Fonts.main(size: 15, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.primary)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(DesignSystem.Colors.primary.opacity(0.10)))
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel("Go to Calendar")
            }

            Button {
                modalCoordinator.activeModal = .addCalendarItem(
                    semesterID: resolvedSemesterID,
                    initialTitle: nil,
                    initialStart: nil,
                    initialEnd: nil
                )
            } label: {
                Image(systemName: "plus")
                    .font(DesignSystem.Fonts.main(size: 16, weight: .bold))
                    .foregroundColor(DesignSystem.Colors.primary)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(DesignSystem.Colors.primary.opacity(0.10)))
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityLabel("Add Event")

            Button {
                guard let resolvedObjectID else { return }
                switch selection {
                case .event:
                    modalCoordinator.activeModal = .editCalendarItem(objectID: resolvedObjectID)
                case .task:
                    modalCoordinator.activeModal = .editTask(objectID: resolvedObjectID)
                }
            } label: {
                Image(systemName: "pencil")
                    .font(DesignSystem.Fonts.main(size: 14, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.textMain)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.black.opacity(0.04)))
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityLabel("Edit")

            Button(role: .destructive) {
                guard let resolvedObjectID else {
                    pillCoordinator.clearSelection()
                    return
                }
                switch selection {
                case .event:
                    attemptGoogleDeleteIfEvent(objectID: resolvedObjectID)
                    coreDataManager.deleteCalendarEvent(objectID: resolvedObjectID)
                case .task:
                    coreDataManager.deleteTask(objectID: resolvedObjectID)
                }
                pillCoordinator.clearSelection()
            } label: {
                Image(systemName: "trash")
                    .font(DesignSystem.Fonts.main(size: 14, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.textMain)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.black.opacity(0.04)))
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityLabel("Delete")
        }
        .frame(maxWidth: 620)
        .onAppear { resolveSelection() }
        .onChange(of: selection) { _, _ in resolveSelection() }
    }

    private func attemptGoogleDeleteIfEvent(objectID: NSManagedObjectID) {
        let context = coreDataManager.viewContext
        if let event = (try? context.existingObject(with: objectID)) as? CalendarEventEntity,
           let localID = event.id {
            Task.detached(priority: .utility) { [calendarManager] in
                calendarManager.deleteEventFromGoogle(localEventID: localID)
            }
        }
    }

    private func resolveSelection() {
        let context = coreDataManager.viewContext
        guard let coordinator = context.persistentStoreCoordinator else {
            resolvedObjectID = nil
            resolvedSemesterID = nil
            title = ""
            subtitle = ""
            return
        }

        switch selection {
        case .event(let uri):
            guard let objectID = coordinator.managedObjectID(forURIRepresentation: uri),
                  let event = (try? context.existingObject(with: objectID)) as? CalendarEventEntity
            else {
                resolvedObjectID = nil
                resolvedSemesterID = nil
                title = "Event"
                subtitle = ""
                return
            }

            resolvedObjectID = objectID
            resolvedSemesterID = event.semester?.id
            let rawTitle = (event.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            title = rawTitle.isEmpty ? "Untitled Event" : rawTitle
            subtitle = Self.eventSubtitle(event)

        case .task(let uri):
            guard let objectID = coordinator.managedObjectID(forURIRepresentation: uri),
                  let task = (try? context.existingObject(with: objectID)) as? TaskEntity
            else {
                resolvedObjectID = nil
                resolvedSemesterID = nil
                title = "Task"
                subtitle = ""
                return
            }

            resolvedObjectID = objectID
            resolvedSemesterID = task.semester?.id
            let rawTitle = (task.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            title = rawTitle.isEmpty ? "Untitled Task" : rawTitle
            subtitle = Self.taskSubtitle(task)
        }
    }

    private static func eventSubtitle(_ event: CalendarEventEntity) -> String {
        var text = ""
        if event.allDay {
            text = "All-day"
        } else if let start = event.startDate, let end = event.endDate {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            formatter.dateStyle = .none
            text = "\(formatter.string(from: start)) – \(formatter.string(from: end))"
        }

        if let location = event.location, !location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if !text.isEmpty { text += " • " }
            text += location
        }
        return text
    }

    private static func taskSubtitle(_ task: TaskEntity) -> String {
        guard let due = task.dueDate else { return "No due date" }
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        return "Due \(df.string(from: due))"
    }
}
