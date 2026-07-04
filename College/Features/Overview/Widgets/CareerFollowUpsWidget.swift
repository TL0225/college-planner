// CareerFollowUpsWidget.swift
// Feature: Overview
// Purpose: Overview module — CareerFollowUpsWidget.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI

struct CareerFollowUpsWidget: View {
    @Environment(AppContainer.self) private var container
    private var persistence: CollegePersistence { container.persistence }
    private var collegePersistence: CollegePersistence { container.persistence }
    @State private var dataRefreshToken = 0

    private var rows: [OverviewCareerFollowUpSummary] {
        _ = collegePersistence.careerDidChangeToken
        _ = dataRefreshToken
        return OverviewReadBridge.careerFollowUps(limit: 3, collegePersistence: collegePersistence)
    }

    var body: some View {
        OverviewCard {
            OverviewWidgetHeader("Career Follow-ups", systemImage: "paperplane.fill", accentColor: .orange)

            Color.clear.frame(height: 16)

            if rows.isEmpty {
                OverviewWidgetEmptyState(
                    title: "No follow-ups queued",
                    message: "Applications that need outreach will show up here.",
                    systemImage: "paperplane",
                    accentColor: .orange
                )
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(rows) { row in
                        followUpRow(row)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background {
            OverviewQueryHost { dataRefreshToken += 1 }
        }
    }

    private func followUpRow(_ row: OverviewCareerFollowUpSummary) -> some View {
        OverviewWidgetRowSurface(accentColor: .orange) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.up.message.fill")
                    .font(DesignSystem.Fonts.main(size: 13, weight: .semibold))
                    .foregroundStyle(.orange)
                    .frame(width: 32, height: 32)
                    .background(Color.orange.opacity(0.12))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(row.company)
                        .font(DesignSystem.Fonts.main(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(row.roleTitle)
                        .font(DesignSystem.Fonts.main(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()
            }
        }
    }

    static var descriptor: WidgetDescriptor {
        WidgetDescriptor(
            id: "career_followups",
            displayName: "Career Follow-ups",
            description: "Upcoming follow-up queue for applications.",
            category: .productivity,
            iconName: "paperplane.fill",
            accentColor: .orange,
            defaultHeight: 170,
            minHeight: 140,
            makePreview: { CareerFollowUpsWidgetPreview() }
        )
    }
}

private struct CareerFollowUpsWidgetPreview: View {
    var body: some View {
        OverviewCard {
            Text("Career Follow-ups").font(.headline)
            Text("Acme Robotics — Robotics Intern")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
