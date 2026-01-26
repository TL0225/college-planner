import SwiftUI
import CoreData
import AppKit

struct CalendarTopPill: View {
    @EnvironmentObject private var coreDataManager: CoreDataManager
    @EnvironmentObject private var modalCoordinator: ModalCoordinator
    @EnvironmentObject private var pillCoordinator: PillCoordinator
    @EnvironmentObject private var calendarManager: CalendarIntegrationManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let selection: PillCoordinator.Selection?
    let selectedSemesterID: UUID?
    var editorDate: Date? = nil
    var onEditSelection: ((NSManagedObjectID, Bool) -> Void)? = nil

    var isCalendarEditorMode: Bool = false
    var onDismissCalendarEditor: (() -> Void)? = nil
    var onSaveCalendarEditor: (() -> Void)? = nil

    @State private var title: String = ""
    @State private var subtitle: String = ""
    @State private var resolvedObjectID: NSManagedObjectID? = nil
    @State private var selectionDate: Date? = nil

    private static let editorDateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = .autoupdatingCurrent
        df.setLocalizedDateFormatFromTemplate("MMM d")
        return df
    }()

    private var hasSelection: Bool { selection != nil }

    var body: some View {
        Group {
            if isCalendarEditorMode {
                ViewThatFits(in: .horizontal) {
                    editorFullLayout
                    editorCompactLayout
                }
            } else if hasSelection {
                ViewThatFits(in: .horizontal) {
                    selectedFullLayout
                    selectedTitleOnlyLayout
                    selectedMinimalLayout
                }
            } else {
                HStack(spacing: 12) {
                    actionIcons
                }
                .fixedSize(horizontal: true, vertical: false)
            }
        }
        .padding(.vertical, hasSelection ? 10 : 7)
        .padding(.horizontal, 14)
        .frame(minHeight: hasSelection ? 52 : 44)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color(nsColor: .separatorColor).opacity(0.7), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 8)
        )
        .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.86), value: hasSelection)
        .onAppear { resolveSelection() }
        .onChange(of: selection) { _, _ in resolveSelection() }
    }

    private var closeButton: some View {
        Button {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                if isCalendarEditorMode {
                    onDismissCalendarEditor?()
                } else {
                    pillCoordinator.clearSelection(animated: !reduceMotion)
                }
            }
        } label: {
            Image(systemName: "xmark")
                .font(DesignSystem.Fonts.main(size: 13, weight: .bold))
                .foregroundColor(DesignSystem.Colors.textMain)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.black.opacity(0.06)))
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Close")
    }

    private var editorFullLayout: some View {
        HStack(spacing: 12) {
            closeButton

            VStack(alignment: .leading, spacing: 2) {
                Text(title.isEmpty ? "Event" : title)
                    .font(DesignSystem.Fonts.main(size: 13, weight: .bold))
                    .foregroundColor(DesignSystem.Colors.textMain)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.90)
                    .allowsTightening(true)

                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.textLight)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .minimumScaleFactor(0.90)
                        .allowsTightening(true)
                }
            }
            .frame(minWidth: 0, alignment: .leading)
            .layoutPriority(1)

            editorActionIcons
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    private var editorCompactLayout: some View {
        HStack(spacing: 12) {
            closeButton
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    editorDateCapsule
                    saveButton
                }
                saveButton
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var editorActionIcons: some View {
        HStack(spacing: 12) {
            editorDateCapsule

            Rectangle()
                .fill(Color.black.opacity(0.10))
                .frame(width: 1, height: 28)

            iconButton(systemName: "trash", tint: DesignSystem.Colors.textMain, enabled: resolvedObjectID != nil) {
                guard let resolvedObjectID else { return }
                switch selection {
                case .event:
                    attemptGoogleDeleteIfEvent(objectID: resolvedObjectID)
                    coreDataManager.deleteCalendarEvent(objectID: resolvedObjectID)
                case .task:
                    coreDataManager.deleteTask(objectID: resolvedObjectID)
                case .none:
                    return
                }
                pillCoordinator.clearSelection(animated: !reduceMotion)
                onDismissCalendarEditor?()
            }

            saveButton
        }
    }

    private var editorDateCapsule: some View {
        let date = selectionDate ?? editorDate ?? Date()
        return HStack(spacing: 8) {
            Image(systemName: "calendar")
                .font(DesignSystem.Fonts.main(size: 12, weight: .bold))
            Text(Self.editorDateFormatter.string(from: date))
                .font(DesignSystem.Fonts.main(size: 13, weight: .bold))
        }
        .foregroundColor(DesignSystem.Colors.primary)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(DesignSystem.Colors.primary.opacity(0.12))
        )
        .fixedSize(horizontal: true, vertical: false)
    }

    private var saveButton: some View {
        Button {
            if let onSaveCalendarEditor {
                onSaveCalendarEditor()
            } else {
                NotificationCenter.default.post(name: .calendarEditorSave, object: nil)
            }
        } label: {
            Image(systemName: "checkmark")
                .font(DesignSystem.Fonts.main(size: 14, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 32, height: 32)
                .background(Circle().fill(DesignSystem.Colors.primary))
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var selectedFullLayout: some View {
        HStack(spacing: 12) {
            closeButton

            VStack(alignment: .leading, spacing: 2) {
                Text(title.isEmpty ? "Event" : title)
                    .font(DesignSystem.Fonts.main(size: 13, weight: .bold))
                    .foregroundColor(DesignSystem.Colors.textMain)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.90)
                    .allowsTightening(true)

                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.textLight)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .minimumScaleFactor(0.90)
                        .allowsTightening(true)
                }
            }
            .frame(minWidth: 0, alignment: .leading)
            .layoutPriority(1)

            actionIcons
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    private var selectedTitleOnlyLayout: some View {
        HStack(spacing: 12) {
            closeButton

            Text(title.isEmpty ? "Event" : title)
                .font(DesignSystem.Fonts.main(size: 13, weight: .bold))
                .foregroundColor(DesignSystem.Colors.textMain)
                .lineLimit(1)
                .truncationMode(.tail)
                .minimumScaleFactor(0.90)
                .allowsTightening(true)
                .frame(minWidth: 0, alignment: .leading)
                .layoutPriority(1)

            actionIcons
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    private var selectedMinimalLayout: some View {
        HStack(spacing: 12) {
            closeButton
            actionIcons
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var actionIcons: some View {
        HStack(spacing: 12) {
            iconButton(systemName: "plus", tint: DesignSystem.Colors.primary, enabled: true) {
                modalCoordinator.activeModal = .addCalendarItem(
                    semesterID: selectedSemesterID,
                    initialTitle: nil,
                    initialStart: nil,
                    initialEnd: nil
                )
            }

            iconButton(systemName: "pencil", tint: DesignSystem.Colors.textMain, enabled: resolvedObjectID != nil) {
                guard let resolvedObjectID else { return }
                let isTask: Bool
                switch selection {
                case .event:
                    isTask = false
                case .task:
                    isTask = true
                case .none:
                    return
                }

                if let onEditSelection {
                    onEditSelection(resolvedObjectID, isTask)
                } else {
                    if isTask {
                        modalCoordinator.activeModal = .editTask(objectID: resolvedObjectID)
                    } else {
                        modalCoordinator.activeModal = .editCalendarItem(objectID: resolvedObjectID)
                    }
                }
            }

            iconButton(systemName: "trash", tint: DesignSystem.Colors.textMain, enabled: resolvedObjectID != nil) {
                guard let resolvedObjectID else { return }
                switch selection {
                case .event:
                    attemptGoogleDeleteIfEvent(objectID: resolvedObjectID)
                    coreDataManager.deleteCalendarEvent(objectID: resolvedObjectID)
                case .task:
                    coreDataManager.deleteTask(objectID: resolvedObjectID)
                case .none:
                    return
                }
                pillCoordinator.clearSelection(animated: !reduceMotion)
            }
        }
    }

    private func attemptGoogleDeleteIfEvent(objectID: NSManagedObjectID) {
        let context = coreDataManager.viewContext
        if let event = (try? context.existingObject(with: objectID)) as? CalendarEventEntity,
           let localID = event.id {
            calendarManager.deleteEventFromGoogle(localEventID: localID)
        }
    }

    private func iconButton(systemName: String, tint: Color, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(DesignSystem.Fonts.main(size: 14, weight: systemName == "plus" ? .bold : .semibold))
                .foregroundColor(tint)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.black.opacity(0.04)))
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
    }

    private func resolveSelection() {
        title = ""
        subtitle = ""
        resolvedObjectID = nil
        selectionDate = nil

        guard let selection else { return }

        let context = coreDataManager.viewContext
        let coordinator = coreDataManager.container.persistentStoreCoordinator

        switch selection {
        case .event(let uri):
            guard let objectID = coordinator.managedObjectID(forURIRepresentation: uri),
                  let event = (try? context.existingObject(with: objectID)) as? CalendarEventEntity
            else {
                title = "Event"
                subtitle = "Details unavailable"
                return
            }

            resolvedObjectID = objectID
            let rawTitle = (event.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            title = rawTitle.isEmpty ? "Untitled Event" : rawTitle
            subtitle = Self.eventSubtitle(event)
            selectionDate = event.startDate ?? event.endDate

        case .task(let uri):
            guard let objectID = coordinator.managedObjectID(forURIRepresentation: uri),
                  let task = (try? context.existingObject(with: objectID)) as? TaskEntity
            else {
                title = "Task"
                subtitle = "Details unavailable"
                return
            }

            resolvedObjectID = objectID
            let rawTitle = (task.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            title = rawTitle.isEmpty ? "Untitled Task" : rawTitle
            subtitle = Self.taskSubtitle(task)
            selectionDate = task.dueDate
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
