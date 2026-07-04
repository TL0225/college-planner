// DeadlinesWidget.swift
// Feature: Overview
// Purpose: Overview module — DeadlinesWidget.
// Data: CollegePersistence / repositories when applicable.

//
//  DeadlinesWidget.swift
//  College
//
//  Shows the next 4 upcoming task deadlines with urgency badges.
//

import SwiftUI

struct DeadlinesWidget: View {
    @Environment(AppContainer.self) private var container
    private var persistence: CollegePersistence { container.persistence }
    private var collegePersistence: CollegePersistence { container.persistence }
    @State private var dataRefreshToken = 0

    private var deadlines: [OverviewTaskSummary] {
        _ = collegePersistence.plannerChangeToken
        _ = dataRefreshToken
        return OverviewReadBridge.pendingTasks(limit: 4, collegePersistence: collegePersistence)
    }

    var body: some View {
        OverviewCard {
            OverviewWidgetHeader("Upcoming Deadlines", systemImage: "exclamationmark.circle.fill", accentColor: WidgetCategory.productivity.accentColor)

            Color.clear.frame(height: 16)

            if deadlines.isEmpty {
                OverviewWidgetEmptyState(
                    title: "No upcoming deadlines",
                    message: "Tasks with due dates will appear here.",
                    systemImage: "calendar.badge.checkmark",
                    accentColor: .green
                )
            } else {
                VStack(spacing: 10) {
                    ForEach(deadlines) { task in
                        deadlineRow(task: task)
                    }
                }
            }
        }
        .background {
            OverviewQueryHost { dataRefreshToken += 1 }
        }
    }

    // MARK: - Row

    private func deadlineRow(task: OverviewTaskSummary) -> some View {
        let urgency = taskUrgency(task)
        return OverviewWidgetRowSurface(accentColor: urgency.dotColor) {
            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .fill(urgency.dotColor)
                    .frame(width: 8, height: 8)
                    .padding(.top, 5)
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.title)
                        .font(DesignSystem.Fonts.main(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if let code = task.courseCode, !code.isEmpty {
                        let detail = [code, task.courseName]
                            .compactMap { value -> String? in
                                guard let value, !value.isEmpty else { return nil }
                                return value
                            }
                            .joined(separator: " • ")
                        if !detail.isEmpty {
                            Text(detail)
                                .font(DesignSystem.Fonts.main(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                Spacer()
                OverviewWidgetBadge(text: urgency.label, color: urgency.labelColor)
            }
        }
    }

    // MARK: - Urgency

    private struct TaskUrgency {
        let dotColor: Color; let label: String
        let labelColor: Color
    }

    private func taskUrgency(_ task: OverviewTaskSummary) -> TaskUrgency {
        let due = task.dueDate
        let days = Calendar.current.dateComponents([.day], from: Date(), to: due).day ?? 0
        if days <= 0 {
            return TaskUrgency(dotColor: .red, label: "TODAY",
                               labelColor: .red)
        } else if days == 1 {
            return TaskUrgency(dotColor: .red, label: "TOMORROW",
                               labelColor: .red)
        } else if days <= 3 {
            return TaskUrgency(dotColor: .orange, label: "\(days) DAYS",
                               labelColor: .orange)
        } else if days <= 7 {
            return TaskUrgency(dotColor: .blue, label: "NEXT WEEK",
                               labelColor: .blue)
        } else {
            let f = DateFormatter(); f.dateFormat = "MMM d"
            return TaskUrgency(dotColor: .green, label: f.string(from: due),
                               labelColor: .green)
        }
    }

    // MARK: - Descriptor

    static var descriptor: WidgetDescriptor {
        WidgetDescriptor(
            id:            "deadlines",
            displayName:   "Upcoming Deadlines",
            description:   "Your next 4 pending tasks sorted by due date with urgency badges.",
            category:      .productivity,
            iconName:      "exclamationmark.circle.fill",
            accentColor:   Color(hex: "EF4444"),
            defaultHeight: 190,
            minHeight:     150,
            makePreview: { DeadlinesWidgetPreview() }
        )
    }
}

// MARK: - Preview

private struct DeadlinesWidgetPreview: View {
    private let items: [(String, String, Color, Color)] = [
        ("CSE 312 — Homework 4",  "TODAY",     Color(hex: "EF4444"), Color(hex: "FEF2F2")),
        ("MTH 309 — Problem Set", "TOMORROW",  Color(hex: "EF4444"), Color(hex: "FEF2F2")),
        ("EE 202 — Lab Report",   "3 DAYS",    Color(hex: "F97316"), Color(hex: "FFF7ED")),
        ("CSE 321 — Project",     "NEXT WEEK", Color(hex: "6366F1"), Color(hex: "EEF2FF")),
    ]
    var body: some View {
        OverviewCard {
            Text("Upcoming Deadlines")
                .font(DesignSystem.Fonts.main(size: 14, weight: .bold, design: .serif))
                .foregroundStyle(DesignSystem.Colors.textMain)
                .padding(.bottom, 10)
            VStack(spacing: 0) {
                ForEach(items.indices, id: \.self) { i in
                    let item = items[i]
                    HStack {
                        Circle().fill(item.2).frame(width: 7, height: 7)
                        Text(item.0).font(DesignSystem.Fonts.main(size: 11)).foregroundStyle(DesignSystem.Colors.textMain).lineLimit(1)
                        Spacer()
                        Text(item.1).font(DesignSystem.Fonts.main(size: 9, weight: .bold)).foregroundStyle(item.2)
                            .padding(.horizontal, 5).padding(.vertical, 2).background(item.3)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .padding(.vertical, 7)
                    if i < items.count - 1 { Divider() }
                }
            }
        }
    }
}
