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
        Group {
        if deadlines.isEmpty {
            VStack(spacing: 0) {
                Text("Upcoming Deadlines")
                    .font(.system(size: 16, weight: .bold, design: .serif))
                    .foregroundColor(DesignSystem.Colors.textMain)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding([.horizontal, .top], 20)
                    .padding(.bottom, 16)
                Spacer()
                Text("No upcoming deadlines")
                    .font(.system(size: 12))
                    .foregroundColor(DesignSystem.Colors.textLight)
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
                Text("Upcoming Deadlines")
                    .font(.system(size: 16, weight: .bold, design: .serif))
                    .foregroundColor(DesignSystem.Colors.textMain)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Color.clear.frame(height: 16)

                VStack(spacing: 0) {
                    ForEach(deadlines) { task in
                        deadlineRow(task: task)
                        if task.id != deadlines.last?.id {
                            Divider().padding(.leading, 18)
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

    // MARK: - Row

    private func deadlineRow(task: OverviewTaskSummary) -> some View {
        let urgency = taskUrgency(task)
        return HStack(alignment: .top, spacing: 10) {
            Circle().fill(urgency.dotColor).frame(width: 8, height: 8).padding(.top, 5)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(task.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.textMain).lineLimit(1)
                    Spacer()
                    Text(urgency.label)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(urgency.labelColor)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(urgency.labelBg)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                if let code = task.courseCode, !code.isEmpty {
                    let detail = [code, task.courseName]
                        .compactMap { value -> String? in
                            guard let value, !value.isEmpty else { return nil }
                            return value
                        }
                        .joined(separator: " • ")
                    if !detail.isEmpty {
                        Text(detail)
                            .font(.system(size: 10)).foregroundColor(DesignSystem.Colors.textLight)
                    }
                }
            }
        }
        .padding(.vertical, 10)
    }

    // MARK: - Urgency

    private struct TaskUrgency {
        let dotColor: Color; let label: String
        let labelColor: Color; let labelBg: Color
    }

    private func taskUrgency(_ task: OverviewTaskSummary) -> TaskUrgency {
        let due = task.dueDate
        let days = Calendar.current.dateComponents([.day], from: Date(), to: due).day ?? 0
        if days <= 0 {
            return TaskUrgency(dotColor: Color(hex: "F87171"), label: "TODAY",
                               labelColor: Color(hex: "EF4444"), labelBg: Color(hex: "FEF2F2"))
        } else if days == 1 {
            return TaskUrgency(dotColor: Color(hex: "F87171"), label: "TOMORROW",
                               labelColor: Color(hex: "EF4444"), labelBg: Color(hex: "FEF2F2"))
        } else if days <= 3 {
            return TaskUrgency(dotColor: Color(hex: "FB923C"), label: "\(days) DAYS",
                               labelColor: Color(hex: "F97316"), labelBg: Color(hex: "FFF7ED"))
        } else if days <= 7 {
            return TaskUrgency(dotColor: Color(hex: "818CF8"), label: "NEXT WEEK",
                               labelColor: Color(hex: "6366F1"), labelBg: Color(hex: "EEF2FF"))
        } else {
            let f = DateFormatter(); f.dateFormat = "MMM d"
            return TaskUrgency(dotColor: Color(hex: "34D399"), label: f.string(from: due),
                               labelColor: Color(hex: "059669"), labelBg: Color(hex: "ECFDF5"))
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
                .font(.system(size: 14, weight: .bold, design: .serif))
                .foregroundColor(DesignSystem.Colors.textMain)
                .padding(.bottom, 10)
            VStack(spacing: 0) {
                ForEach(items.indices, id: \.self) { i in
                    let item = items[i]
                    HStack {
                        Circle().fill(item.2).frame(width: 7, height: 7)
                        Text(item.0).font(.system(size: 11)).foregroundColor(DesignSystem.Colors.textMain).lineLimit(1)
                        Spacer()
                        Text(item.1).font(.system(size: 9, weight: .bold)).foregroundColor(item.2)
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
