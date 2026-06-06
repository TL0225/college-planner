// CareerPipelineWidget.swift
// Feature: Overview
// Purpose: Overview module — CareerPipelineWidget.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI
import CollegeCareer

struct CareerPipelineWidget: View {
    @Environment(AppContainer.self) private var container
    private var persistence: CollegePersistence { container.persistence }
    private var collegePersistence: CollegePersistence { container.persistence }
    @State private var dataRefreshToken = 0

    var onNavigateToCareer: (CareerApplicationStatus) -> Void = { _ in }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var statusCounts: [CareerApplicationStatus: Int] {
        _ = collegePersistence.careerDidChangeToken
        _ = dataRefreshToken
        return CareerReadBridge.statusCounts() ?? [:]
    }

    var body: some View {
        OverviewCard {
            Text("Career Pipeline")
                .font(DesignSystem.Fonts.title3(weight: .bold))
            HStack {
                pipelineMetric("Applied", status: .applied)
                pipelineMetric("Interview", status: .interviewing)
                pipelineMetric("Offer", status: .offer)
            }
            .padding(.top, DesignSystem.Spacing.sm)
        }
        .background {
            OverviewQueryHost { dataRefreshToken += 1 }
        }
    }

    private func count(status: CareerApplicationStatus) -> Int {
        statusCounts[status] ?? 0
    }

    private func pipelineMetric(_ title: String, status: CareerApplicationStatus) -> some View {
        let value = count(status: status)
        return Button {
            onNavigateToCareer(status)
        } label: {
            VStack(spacing: DesignSystem.Spacing.xs) {
                Text("\(value)")
                    .font(DesignSystem.Fonts.title2())
                    .contentTransition(reduceMotion ? .opacity : .numericText(value: Double(value)))
                Text(title)
                    .font(DesignSystem.Fonts.caption1())
                    .foregroundStyle(DesignSystem.Colors.textLight)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DesignSystem.Spacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .symbolEffect(.bounce, value: value)
        .accessibilityLabel("\(title), \(value) applications")
        .accessibilityHint("Opens Career board filtered to \(title)")
    }

    static var descriptor: WidgetDescriptor {
        WidgetDescriptor(
            id: "career_pipeline",
            displayName: "Career Pipeline",
            description: "Snapshot of current application funnel.",
            category: .productivity,
            iconName: "briefcase.fill",
            accentColor: .purple,
            defaultHeight: 170,
            minHeight: 140,
            makePreview: { CareerPipelineWidgetPreview() }
        )
    }
}

private struct CareerPipelineWidgetPreview: View {
    var body: some View {
        OverviewCard {
            Text("Career Pipeline").font(DesignSystem.Fonts.headline())
            HStack {
                Text("Applied 8")
                Text("Interview 3")
                Text("Offer 1")
            }
            .font(DesignSystem.Fonts.caption1())
            .foregroundStyle(.secondary)
        }
    }
}
