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
            OverviewWidgetHeader("Career Pipeline", systemImage: "briefcase.fill", accentColor: .purple)

            Color.clear.frame(height: 16)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    pipelineMetric("Applied", status: .applied, color: .blue)
                    pipelineMetric("Interview", status: .interviewing, color: .purple)
                    pipelineMetric("Offer", status: .offer, color: .green)
                }

                VStack(spacing: 10) {
                    pipelineMetric("Applied", status: .applied, color: .blue)
                    pipelineMetric("Interview", status: .interviewing, color: .purple)
                    pipelineMetric("Offer", status: .offer, color: .green)
                }
            }
        }
        .background {
            OverviewQueryHost { dataRefreshToken += 1 }
        }
    }

    private func count(status: CareerApplicationStatus) -> Int {
        statusCounts[status] ?? 0
    }

    private func pipelineMetric(_ title: String, status: CareerApplicationStatus, color: Color) -> some View {
        let value = count(status: status)
        return Button {
            onNavigateToCareer(status)
        } label: {
            OverviewWidgetRowSurface(accentColor: color) {
                VStack(spacing: 4) {
                    Text("\(value)")
                        .font(DesignSystem.Fonts.main(size: 30, weight: .heavy, design: .rounded))
                        .foregroundStyle(color)
                        .monospacedDigit()
                        .contentTransition(reduceMotion ? .opacity : .numericText(value: Double(value)))
                    Text(title.uppercased())
                        .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
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
