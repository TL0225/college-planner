// OverviewNeedsAttention.swift
// Feature: Overview
// Purpose: Overview module — Tier 1 "Needs Attention" priority strip.
// Data: CollegePersistence / repositories when applicable.

import CollegeCalendar
import SwiftUI

/// The Overview's top-priority strip — the "what do I need to do today?" answer.
///
/// It aggregates the most time-sensitive items across domains (today's events,
/// deadlines due soon, pending interviews) via `OverviewReadBridge`, ranks them
/// by time, and collapses to a single calm line when there is nothing urgent so
/// a fresh account never sees an alarming empty card.
struct NeedsAttentionCard: View {
    @Environment(AppContainer.self) private var container
    private var calendarManager: CalendarIntegrationManager { container.calendarManager }
    private var collegePersistence: CollegePersistence { container.persistence }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("ui.reduceMotion") private var appReduceMotion = false

    var onSelect: (OverviewAttentionItem) -> Void = { _ in }
    var onAskAssistant: () -> Void = {}

    @State private var dataRefreshToken = 0

    private var motionReduced: Bool { reduceMotion || appReduceMotion }

    private var items: [OverviewAttentionItem] {
        _ = collegePersistence.calendarDidChangeToken
        _ = collegePersistence.plannerChangeToken
        _ = collegePersistence.careerDidChangeToken
        _ = dataRefreshToken
        return OverviewReadBridge.needsAttentionItems(
            limit: 4,
            calendarManager: calendarManager,
            collegePersistence: collegePersistence
        )
    }

    var body: some View {
        let items = items
        OverviewCard {
            OverviewWidgetHeader("Needs Attention", systemImage: "bolt.fill", accentColor: .accentColor) {
                Button {
                    onAskAssistant()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                        Text("Ask Assistant")
                    }
                    .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.accentColor.opacity(0.12))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            Color.clear.frame(height: 16)

            if items.isEmpty {
                emptyState
            } else {
                VStack(spacing: 8) {
                    ForEach(items) { item in
                        attentionRow(item)
                    }
                }
            }
        }
        .background {
            OverviewQueryHost { dataRefreshToken += 1 }
        }
    }

    private var emptyState: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(DesignSystem.Fonts.main(size: 18, weight: .semibold))
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text("You're all caught up")
                    .font(DesignSystem.Fonts.main(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("Nothing urgent today. Plan ahead or ask the assistant.")
                    .font(DesignSystem.Fonts.main(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    private func attentionRow(_ item: OverviewAttentionItem) -> some View {
        let style = rowStyle(for: item)
        return Button {
            onSelect(item)
        } label: {
            OverviewWidgetRowSurface(accentColor: style.color) {
                HStack(spacing: 12) {
                    Image(systemName: style.icon)
                        .font(DesignSystem.Fonts.main(size: 14, weight: .semibold))
                        .foregroundStyle(style.color)
                        .frame(width: 34, height: 34)
                        .background(style.color.opacity(0.12))
                        .clipShape(Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(DesignSystem.Fonts.main(size: 14, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        if let subtitle = item.subtitle, !subtitle.isEmpty {
                            Text(subtitle)
                                .font(DesignSystem.Fonts.main(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 8)
                    OverviewWidgetBadge(text: relativeLabel(for: item), color: style.color)
                }
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
    }

    private struct RowStyle {
        let icon: String
        let color: Color
    }

    private func rowStyle(for item: OverviewAttentionItem) -> RowStyle {
        switch item.kind {
        case .event:
            return RowStyle(icon: "calendar", color: .accentColor)
        case .deadline:
            let isUrgent: Bool = {
                guard let date = item.date else { return false }
                let days = Calendar.current.dateComponents(
                    [.day],
                    from: Calendar.current.startOfDay(for: Date()),
                    to: Calendar.current.startOfDay(for: date)
                ).day ?? 0
                return days <= 1
            }()
            return RowStyle(icon: "exclamationmark.circle.fill", color: isUrgent ? .red : .orange)
        case .interview:
            return RowStyle(icon: "briefcase.fill", color: .purple)
        }
    }

    private func relativeLabel(for item: OverviewAttentionItem) -> String {
        guard let date = item.date else { return "SOON" }
        let now = Date()
        if date <= now { return "NOW" }
        let cal = Calendar.current
        let minutes = Int(date.timeIntervalSince(now) / 60)
        if minutes < 60 { return "IN \(max(minutes, 1))M" }
        if cal.isDateInToday(date) {
            let f = DateFormatter()
            f.dateFormat = "h:mm a"
            return f.string(from: date).uppercased()
        }
        if cal.isDateInTomorrow(date) { return "TOMORROW" }
        let days = cal.dateComponents(
            [.day],
            from: cal.startOfDay(for: now),
            to: cal.startOfDay(for: date)
        ).day ?? 0
        return "IN \(days)D"
    }
}
