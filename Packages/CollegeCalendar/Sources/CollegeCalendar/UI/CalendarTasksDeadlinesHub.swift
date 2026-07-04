// CalendarTasksDeadlinesHub.swift
// Feature: Calendar (Phase 4 — M30-088)
// Purpose: Smart lists + Study/Focus filtering for the calendar tasks inspector.

import Foundation
import SwiftUI

public enum CalendarNotificationNames {
    public static let selectSidebarPanel = Notification.Name("college.calendarSelectSidebarPanel")
}

extension Notification.Name {
    public static let collegeCalendarSelectSidebarPanel = CalendarNotificationNames.selectSidebarPanel
}

public enum CalendarSmartList: String, CaseIterable, Identifiable, Sendable {
    case overdue = "Overdue"
    case dueToday = "Due Today"
    case thisWeek = "This Week"
    case allOpen = "All Open"
    case studyFocus = "Study / Focus"

    public var id: String { rawValue }

    public var systemImage: String {
        switch self {
        case .overdue: return "exclamationmark.circle"
        case .dueToday: return "sun.max"
        case .thisWeek: return "calendar"
        case .allOpen: return "tray.full"
        case .studyFocus: return "brain.head.profile"
        }
    }

    public var description: String {
        switch self {
        case .overdue:
            return "Tasks with due dates before today."
        case .dueToday:
            return "Tasks due before midnight tonight."
        case .thisWeek:
            return "Tasks due in the next seven days."
        case .allOpen:
            return "All incomplete tasks in this date range."
        case .studyFocus:
            return "Tasks with study, exam, or homework keywords."
        }
    }
}

public enum CalendarTasksDeadlinesHub {
  private static let studyKeywords = [
        "study", "exam", "quiz", "homework", "assignment", "reading", "focus", "review", "problem set", "pset"
    ]

    @MainActor
    public static func fetchOpenTasks(
        rangeStart: Date,
        rangeEnd: Date,
        limit: Int = 400
    ) -> [CalendarPlannerTaskSummary] {
        guard let repo = CalendarPersistenceAccess.writeRepository,
              let tasks = try? repo.fetchTasks(dueFrom: rangeStart, dueBefore: rangeEnd, limit: limit) else {
            return []
        }
        return tasks.map { CalendarPlannerTaskSummary(task: $0) }
    }

    public static func filter(
        _ tasks: [CalendarPlannerTaskSummary],
        list: CalendarSmartList,
        reference: Date = Date(),
        calendar: Calendar = .current
    ) -> [CalendarPlannerTaskSummary] {
        let todayStart = calendar.startOfDay(for: reference)
        let todayEnd = calendar.date(byAdding: .day, value: 1, to: todayStart) ?? todayStart.addingTimeInterval(86_400)
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: todayStart) ?? todayEnd

        let filtered: [CalendarPlannerTaskSummary]
        switch list {
        case .overdue:
            filtered = tasks.filter { task in
                guard let due = task.dueDate else { return false }
                return due < todayStart
            }
        case .dueToday:
            filtered = tasks.filter { task in
                guard let due = task.dueDate else { return false }
                return due >= todayStart && due < todayEnd
            }
        case .thisWeek:
            filtered = tasks.filter { task in
                guard let due = task.dueDate else { return false }
                return due >= todayStart && due < weekEnd
            }
        case .allOpen:
            filtered = tasks
        case .studyFocus:
            filtered = tasks.filter(isStudyFocused)
        }

        return filtered.sorted { lhs, rhs in
            let ld = lhs.dueDate ?? .distantFuture
            let rd = rhs.dueDate ?? .distantFuture
            if ld != rd { return ld < rd }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    public static func isStudyFocused(_ task: CalendarPlannerTaskSummary) -> Bool {
        let haystack = task.title.lowercased()
        return studyKeywords.contains { haystack.contains($0) }
    }
}

public struct CalendarTasksDeadlinesPanel: View {
    let tasks: [CalendarPlannerTaskSummary]
    @Binding var selectedList: CalendarSmartList
    let sidebarDateLabel: String
    let reduceMotion: Bool
    let onAddTask: () -> Void
    let taskRow: (CalendarPlannerTaskSummary) -> AnyView

    public init(
        tasks: [CalendarPlannerTaskSummary],
        selectedList: Binding<CalendarSmartList>,
        sidebarDateLabel: String,
        reduceMotion: Bool,
        onAddTask: @escaping () -> Void,
        taskRow: @escaping (CalendarPlannerTaskSummary) -> AnyView
    ) {
        self.tasks = tasks
        _selectedList = selectedList
        self.sidebarDateLabel = sidebarDateLabel
        self.reduceMotion = reduceMotion
        self.onAddTask = onAddTask
        self.taskRow = taskRow
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            smartListPicker
            taskScroll
            addButton
        }
        .inspectorSidebarBackground()
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Tasks & Deadlines")
                    .font(DesignSystem.Fonts.main(size: 18, weight: .bold))
                    .foregroundStyle(.primary)
                    .accessibilityIdentifier("calendar.tasksDeadlines.title")
                Text(sidebarDateLabel)
                    .font(DesignSystem.Fonts.main(size: 11, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private var smartListPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(CalendarSmartList.allCases) { list in
                        Button {
                            selectedList = list
                        } label: {
                            Label(list.rawValue, systemImage: list.systemImage)
                                .font(DesignSystem.Fonts.main(size: 11, weight: .semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    selectedList == list
                                        ? Color.accentColor.opacity(0.18)
                                        : Color.primary.opacity(0.06),
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(.plain)
                        .help(list.description)
                        .accessibilityIdentifier("calendar.smartList.\(list.rawValue)")
                    }
                }
                .padding(.horizontal, 20)
            }
            Text(selectedList.description)
                .font(DesignSystem.Fonts.main(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .accessibilityIdentifier("calendar.smartList.description")
        }
        .padding(.bottom, 12)
    }

    private var taskScroll: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(spacing: 12) {
                if tasks.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: selectedList == .studyFocus ? "brain.head.profile" : "checklist")
                            .font(DesignSystem.Fonts.main(size: 28))
                            .foregroundStyle(.tertiary)
                        Text(emptyCopy)
                            .font(DesignSystem.Fonts.main(size: 14, weight: .medium))
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 24)
                } else {
                    ForEach(tasks) { task in
                        taskRow(task)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .scrollBounceBehavior(.basedOnSize)
    }

    private var emptyCopy: String {
        switch selectedList {
        case .studyFocus:
            return "No study or focus tasks in this range."
        case .overdue:
            return "Nothing overdue — nice work."
        default:
            return "No tasks in this list."
        }
    }

    private var addButton: some View {
        Button(action: onAddTask) {
            Text("Add Task")
                .font(DesignSystem.Fonts.main(size: 14, weight: .bold))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(DesignSystem.Colors.chromeStroke, lineWidth: 1)
                )
        }
        .buttonStyle(TasksDeadlinesPressableStyle(reduceMotion: reduceMotion))
        .pointerStyle(.link)
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 20)
        .accessibilityIdentifier("calendar.tasksDeadlines.addTask")
    }
}

private struct TasksDeadlinesPressableStyle: ButtonStyle {
    var reduceMotion: Bool = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1.0)
            .animation(.spring(response: 0.10, dampingFraction: 0.72), value: configuration.isPressed)
    }
}
