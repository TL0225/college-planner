// TasksWidget.swift
// Feature: Overview
// Purpose: Overview module — TasksWidget.
// Data: CollegePersistence / repositories when applicable.

//
//  TasksWidget.swift
//  College
//
//  Shows pending tasks (up to 5) with priority badges and due-date labels.
//

import SwiftUI

struct TasksWidget: View {
    @Environment(AppContainer.self) private var container
    private var persistence: CollegePersistence { container.persistence }
    private var modalCoordinator: ModalCoordinator { container.modalCoordinator }
    private var collegePersistence: CollegePersistence { container.persistence }
    @State private var dataRefreshToken = 0

    private var allPending: [OverviewTaskSummary] {
        _ = collegePersistence.plannerChangeToken
        _ = dataRefreshToken
        return OverviewReadBridge.pendingTasks(limit: 5, collegePersistence: collegePersistence)
    }

    var body: some View {
        OverviewCard {
            OverviewWidgetHeader("My Tasks", systemImage: "checkmark.circle.fill", accentColor: WidgetCategory.productivity.accentColor) {
                addButton
            }

            Color.clear.frame(height: 14)

            if allPending.isEmpty {
                OverviewWidgetEmptyState(
                    title: "All caught up",
                    message: "New assignments and reminders will appear here.",
                    systemImage: "checkmark.circle.fill",
                    accentColor: .green
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(allPending) { task in
                        taskRow(task)
                        if task.id != allPending.last?.id {
                            Divider().padding(.leading, 32)
                        }
                    }
                }
            }
        }
        .background {
            OverviewQueryHost { dataRefreshToken += 1 }
        }
        .overviewWidgetSurface(id: "tasks", title: "My Tasks")
    }

    private var addButton: some View {
        Button(action: {
            modalCoordinator.activeModal = .addTask(semesterID: nil, prefillCourseID: nil)
        }) {
            Image(systemName: "plus")
                .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 22, height: 22)
                .background(Color.accentColor.opacity(0.12))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add task")
        .accessibilityHint("Opens task editor")
    }

    // MARK: - Row

    private func taskRow(_ task: OverviewTaskSummary) -> some View {
        let priority = task.priority
        let (priorityLabel, priorityColor) = priorityInfo(priority)
        return OverviewWidgetRowSurface(accentColor: priorityColor) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "circle")
                    .font(DesignSystem.Fonts.main(size: 14, weight: .light))
                    .foregroundStyle(priorityColor)
                    .frame(width: 20)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.title)
                        .font(DesignSystem.Fonts.main(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        OverviewWidgetBadge(text: priorityLabel, color: priorityColor)
                        Text(dueDateLabel(task.dueDate))
                            .font(DesignSystem.Fonts.main(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
        }
    }

    private func priorityInfo(_ priority: Int) -> (String, Color) {
        switch priority {
        case 2...: return ("HIGH", .red)
        case 1:    return ("MEDIUM", .orange)
        default:   return ("LOW", .green)
        }
    }

    private func dueDateLabel(_ date: Date) -> String {
        let days = Calendar.current.dateComponents([.day], from: Date(), to: date).day ?? 0
        if days <= 0 { return "Due today" }
        if days == 1 { return "Due tomorrow" }
        if days < 7  { return "Due in \(days) days" }
        let f = DateFormatter(); f.dateFormat = "MMM d"
        return "Due \(f.string(from: date))"
    }

    // MARK: - Descriptor

    static var descriptor: WidgetDescriptor {
        WidgetDescriptor(
            id:            "tasks",
            displayName:   "My Tasks",
            description:   "Up to 5 pending tasks with priority badges and due dates.",
            category:      .productivity,
            iconName:      "checkmark.circle.fill",
            accentColor:   Color(hex: "F59E0B"),
            defaultHeight: 190,
            minHeight:     150,
            makePreview: { TasksWidgetPreview() }
        )
    }
}

// MARK: - Preview

private struct TasksWidgetPreview: View {
    private let tasks: [(String, String, Color, Color)] = [
        ("Finish CSE 312 homework",    "HIGH",   Color(hex: "EF4444"), Color(hex: "FEF2F2")),
        ("Read chapter 7 — MTH 309",   "MEDIUM", Color(hex: "F59E0B"), Color(hex: "FFFBEB")),
        ("Review lecture notes",        "LOW",    Color(hex: "10B981"), Color(hex: "ECFDF5")),
        ("Submit SBU research form",    "MEDIUM", Color(hex: "F59E0B"), Color(hex: "FFFBEB")),
    ]
    var body: some View {
        OverviewCard {
            Text("My Tasks")
                .font(DesignSystem.Fonts.main(size: 14, weight: .bold, design: .serif))
                .foregroundStyle(DesignSystem.Colors.textMain).padding(.bottom, 10)
            VStack(spacing: 0) {
                ForEach(tasks.indices, id: \.self) { i in
                    let t = tasks[i]
                    HStack(spacing: 8) {
                        Image(systemName: "circle").font(DesignSystem.Fonts.main(size: 12)).foregroundStyle(t.2)
                        Text(t.0).font(DesignSystem.Fonts.main(size: 11)).foregroundStyle(DesignSystem.Colors.textMain).lineLimit(1)
                        Spacer()
                        Text(t.1).font(DesignSystem.Fonts.main(size: 9, weight: .bold)).foregroundStyle(t.2)
                            .padding(.horizontal, 5).padding(.vertical, 2).background(t.3)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                    .padding(.vertical, 6)
                    if i < tasks.count - 1 { Divider() }
                }
            }
        }
    }
}
