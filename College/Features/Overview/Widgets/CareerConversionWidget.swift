// CareerConversionWidget.swift
// Feature: Overview
// Purpose: Overview module — CareerConversionWidget.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI

struct CareerConversionWidget: View {
    @Environment(AppContainer.self) private var container
    private var persistence: CollegePersistence { container.persistence }
    private var collegePersistence: CollegePersistence { container.persistence }
    @State private var dataRefreshToken = 0

    private var pipelineMetrics: CollegePersistence.CareerPipelineMetrics {
        _ = collegePersistence.careerDidChangeToken
        _ = dataRefreshToken
        return CareerReadBridge.pipelineMetrics()
    }

    private var applied: Int { pipelineMetrics.totalApplied }
    private var interview: Int { pipelineMetrics.interviews }
    private var offer: Int { pipelineMetrics.offers }

    var body: some View {
        OverviewCard {
            Text("Career Conversion")
                .font(DesignSystem.Fonts.main(size: 16, weight: .bold, design: .serif))
            VStack(alignment: .leading, spacing: 6) {
                conversion("Interview Rate", applied == 0 ? 0 : Int(Double(interview) / Double(applied) * 100))
                conversion("Offer Rate", applied == 0 ? 0 : Int(Double(offer) / Double(applied) * 100))
            }
            .padding(.top, 8)
        }
        .background {
            OverviewQueryHost { dataRefreshToken += 1 }
        }
    }

    private func conversion(_ label: String, _ value: Int) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text("\(value)%").font(.caption.weight(.semibold))
        }
    }

    static var descriptor: WidgetDescriptor {
        WidgetDescriptor(
            id: "career_conversion",
            displayName: "Career Conversion",
            description: "Interview and offer conversion metrics.",
            category: .information,
            iconName: "chart.bar.fill",
            accentColor: .green,
            defaultHeight: 160,
            minHeight: 130,
            makePreview: { CareerConversionWidgetPreview() }
        )
    }
}

private struct CareerConversionWidgetPreview: View {
    var body: some View {
        OverviewCard {
            Text("Career Conversion").font(.headline)
            Text("Interview 42% • Offer 14%")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
