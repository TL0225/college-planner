// CareerStatsView.swift
// Feature: Career
// Purpose: Career module — CareerStatsView.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI
import Charts

struct CareerStatsView: View {
    @EnvironmentObject private var collegePersistence: CollegePersistence
    @State private var statsRows: [CareerApplicationStatsRow] = []

    private var pipelineCounts: [(status: CareerApplicationStatus, count: Int)] {
        CareerReadBridge.pipelineCountsForCharts(from: statsRows)
    }

    private var weeklyApplications: [(week: Date, count: Int)] {
        CareerReadBridge.weeklyApplications(from: statsRows)
    }

    private var companyResponseRates: [(company: String, applied: Int, advanced: Int)] {
        CareerReadBridge.companyResponseRates(from: statsRows)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                Text("Application stats")
                    .font(DesignSystem.Fonts.title1())

                if !pipelineCounts.isEmpty {
                    statCard(title: "Pipeline funnel") {
                        Chart(pipelineCounts, id: \.status) { item in
                            BarMark(
                                x: .value("Count", item.count),
                                y: .value("Stage", item.status.displayName)
                            )
                            .foregroundStyle(by: .value("Stage", item.status.displayName))
                        }
                        .frame(height: CGFloat(max(120, pipelineCounts.count * 36)))
                    }
                }

                statCard(title: "Applications per week") {
                    Chart(weeklyApplications, id: \.week) { item in
                        BarMark(
                            x: .value("Week", item.week, unit: .weekOfYear),
                            y: .value("Count", item.count)
                        )
                    }
                    .frame(height: 180)
                }

                statCard(title: "Response rate by company") {
                    if companyResponseRates.isEmpty {
                        Text("Track applications on the Board to see stats.")
                            .font(DesignSystem.Fonts.caption1())
                            .foregroundStyle(DesignSystem.Colors.textLight)
                    } else {
                        VStack(spacing: DesignSystem.Spacing.sm) {
                            ForEach(companyResponseRates, id: \.company) { row in
                                HStack {
                                    Text(row.company)
                                        .font(DesignSystem.Fonts.body())
                                        .lineLimit(1)
                                    Spacer()
                                    Text("\(row.advanced)/\(row.applied) advanced")
                                        .font(DesignSystem.Fonts.caption1().monospacedDigit())
                                        .foregroundStyle(DesignSystem.Colors.textLight)
                                }
                            }
                        }
                    }
                }
            }
            .padding(DesignSystem.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignSystem.Colors.bgMain)
        .onAppear { reloadStats() }
        .onChange(of: collegePersistence.careerDidChangeToken) { _, _ in reloadStats() }
        .background {
            CareerQueryHost {
                reloadStats()
            }
        }
    }

    private func reloadStats() {
        statsRows = CareerReadBridge.applicationStatsRows()
    }

    private func statCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            Text(title)
                .font(DesignSystem.Fonts.headline(weight: .semibold))
                .foregroundStyle(DesignSystem.Colors.textMain)
            content()
        }
        .padding(DesignSystem.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignSystem.Colors.surface, in: RoundedRectangle(cornerRadius: DesignSystem.Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
        )
    }
}

enum CareerBoardMarkdownExport {
    static func table(from applications: [JobApplication]) -> String {
        var lines = ["| Company | Role | Status | Applied | Notes |", "|---|---|---|---|---|"]
        let df = DateFormatter()
        df.dateStyle = .medium
        for app in applications.sorted(by: { ($0.company ?? "") < ($1.company ?? "") }) {
            let company = (app.company ?? "").replacingOccurrences(of: "|", with: "\\|")
            let title = (app.title ?? "").replacingOccurrences(of: "|", with: "\\|")
            let status = CareerApplicationPresentation.status(for: app).displayName
            let date = (app.lastStatusChangeAt ?? app.createdAt).map { df.string(from: $0) } ?? ""
            let loc = (app.locationText ?? "").replacingOccurrences(of: "|", with: "\\|")
            lines.append("| \(company) | \(title) | \(status) | \(date) | \(loc) |")
        }
        return lines.joined(separator: "\n")
    }
}
