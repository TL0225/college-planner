// CareerFollowUpsWidget.swift
// Feature: Overview
// Purpose: Overview module — CareerFollowUpsWidget.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI

struct CareerFollowUpsWidget: View {
    @EnvironmentObject private var collegePersistence: CollegePersistence
    @State private var dataRefreshToken = 0

    private var rows: [OverviewCareerFollowUpSummary] {
        _ = collegePersistence.careerDidChangeToken
        _ = dataRefreshToken
        return OverviewReadBridge.careerFollowUps(limit: 3, collegePersistence: collegePersistence)
    }

    var body: some View {
        OverviewCard {
            Text("Career Follow-ups")
                .font(DesignSystem.Fonts.main(size: 16, weight: .bold, design: .serif))
            VStack(alignment: .leading, spacing: 6) {
                ForEach(rows) { row in
                    Text("\(row.company) - \(row.roleTitle)")
                        .font(.caption)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 6)
        }
        .background {
            OverviewQueryHost { dataRefreshToken += 1 }
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
