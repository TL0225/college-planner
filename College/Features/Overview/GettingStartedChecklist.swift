// GettingStartedChecklist.swift
// Feature: Overview
// Purpose: First-run setup checklist card surfaced on the Overview tab.
// Data: Completion signals supplied by OverviewView from app stores.

import SwiftUI

/// A single actionable setup step shown in the Getting Started card.
struct GettingStartedItem: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    let isComplete: Bool
    let action: () -> Void
}

/// Dismissible first-run checklist that guides a new user through initial setup.
///
/// Each row deep-links to the relevant area and renders as complete once its
/// underlying signal is satisfied. The parent is responsible for hiding the
/// card when every item is complete or the user dismisses it.
struct GettingStartedChecklist: View {
    let items: [GettingStartedItem]
    let onDismiss: () -> Void

    private var completedCount: Int { items.filter(\.isComplete).count }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Getting Started")
                        .font(DesignSystem.Fonts.main(size: 17, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.textMain)
                    Text("\(completedCount) of \(items.count) complete")
                        .font(DesignSystem.Fonts.main(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(DesignSystem.Fonts.main(size: 16))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Dismiss the Getting Started checklist")
                .accessibilityLabel("Dismiss Getting Started checklist")
            }

            ProgressView(value: Double(completedCount), total: Double(max(items.count, 1)))
                .tint(DesignSystem.Colors.primary)

            VStack(spacing: 0) {
                ForEach(items) { item in
                    Button {
                        item.action()
                    } label: {
                        HStack(spacing: DesignSystem.Spacing.md) {
                            Image(systemName: item.isComplete ? "checkmark.circle.fill" : item.systemImage)
                                .font(DesignSystem.Fonts.main(size: 16))
                                .foregroundStyle(item.isComplete ? AnyShapeStyle(DesignSystem.Colors.success) : AnyShapeStyle(Color.secondary))
                                .frame(width: 22)
                                .accessibilityHidden(true)
                            Text(item.title)
                                .font(DesignSystem.Fonts.main(size: 13))
                                .strikethrough(item.isComplete, color: .secondary)
                                .foregroundStyle(item.isComplete ? .secondary : .primary)
                            Spacer()
                            if !item.isComplete {
                                Image(systemName: "chevron.forward")
                                    .font(DesignSystem.Fonts.main(size: 11, weight: .semibold))
                                    .foregroundStyle(.tertiary)
                                    .accessibilityHidden(true)
                            }
                        }
                        .padding(.vertical, DesignSystem.Spacing.sm)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(item.isComplete)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(item.isComplete ? "\(item.title), completed" : item.title)

                    if item.id != items.last?.id {
                        Divider()
                    }
                }
            }
        }
        .cardSurface()
    }
}
