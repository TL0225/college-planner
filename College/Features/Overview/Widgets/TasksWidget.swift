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
    @Environment(ModalCoordinator.self) private var modalCoordinator
    @EnvironmentObject private var collegePersistence: CollegePersistence
    @State private var dataRefreshToken = 0

    private var allPending: [OverviewTaskSummary] {
        _ = collegePersistence.plannerChangeToken
        _ = dataRefreshToken
        return OverviewReadBridge.pendingTasks(limit: 5, collegePersistence: collegePersistence)
    }

    var body: some View {
        Group {
        if allPending.isEmpty {
            VStack(spacing: 0) {
                HStack {
                    Text("My Tasks")
                        .font(.system(size: 16, weight: .bold, design: .serif))
                        .foregroundColor(DesignSystem.Colors.textMain)
                    Spacer()
                    addButton
                }
                .padding([.horizontal, .top], 20).padding(.bottom, 14)
                Spacer()
                Label("All caught up!", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12)).foregroundColor(Color(hex: "10B981"))
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DesignSystem.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .shadow(color: .black.opacity(0.04), radius: 12, x: 0, y: 4)
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color(hex: "F3F4F6"), lineWidth: 1))
        } else {
            OverviewCard {
                HStack {
                    Text("My Tasks")
                        .font(.system(size: 16, weight: .bold, design: .serif))
                        .foregroundColor(DesignSystem.Colors.textMain)
                    Spacer()
                    addButton
                }
                Color.clear.frame(height: 14)
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
        }
        .background {
            OverviewQueryHost { dataRefreshToken += 1 }
        }
    }

    private var addButton: some View {
        Button(action: {
            modalCoordinator.activeModal = .addTask(semesterID: nil, prefillCourseID: nil)
        }) {
            Image(systemName: "plus")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(Color(hex: "6366F1"))
                .frame(width: 22, height: 22)
                .background(Color(hex: "EEF2FF"))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Row

    private func taskRow(_ task: OverviewTaskSummary) -> some View {
        let priority = task.priority
        let (priorityLabel, priorityColor, priorityBg) = priorityInfo(priority)
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: "circle")
                .font(.system(size: 14, weight: .light)).foregroundColor(priorityColor)
                .frame(width: 20).padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .font(.system(size: 12, weight: .medium)).foregroundColor(DesignSystem.Colors.textMain).lineLimit(1)
                HStack(spacing: 6) {
                    Text(priorityLabel)
                        .font(.system(size: 9, weight: .bold)).foregroundColor(priorityColor)
                        .padding(.horizontal, 5).padding(.vertical, 2).background(priorityBg)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                    Text(dueDateLabel(task.dueDate)).font(.system(size: 10)).foregroundColor(DesignSystem.Colors.textLight)
                }
            }
            Spacer()
        }
        .padding(.vertical, 8)
    }

    private func priorityInfo(_ priority: Int) -> (String, Color, Color) {
        switch priority {
        case 2...: return ("HIGH",   Color(hex: "EF4444"), Color(hex: "FEF2F2"))
        case 1:    return ("MEDIUM", Color(hex: "F59E0B"), Color(hex: "FFFBEB"))
        default:   return ("LOW",    Color(hex: "10B981"), Color(hex: "ECFDF5"))
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
                .font(.system(size: 14, weight: .bold, design: .serif))
                .foregroundColor(DesignSystem.Colors.textMain).padding(.bottom, 10)
            VStack(spacing: 0) {
                ForEach(tasks.indices, id: \.self) { i in
                    let t = tasks[i]
                    HStack(spacing: 8) {
                        Image(systemName: "circle").font(.system(size: 12)).foregroundColor(t.2)
                        Text(t.0).font(.system(size: 11)).foregroundColor(DesignSystem.Colors.textMain).lineLimit(1)
                        Spacer()
                        Text(t.1).font(.system(size: 9, weight: .bold)).foregroundColor(t.2)
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
