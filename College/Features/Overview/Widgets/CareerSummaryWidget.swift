// CareerSummaryWidget.swift
// Feature: Overview
// Purpose: Overview module — combined Career status (pipeline + follow-ups).
// Data: CollegePersistence / repositories when applicable.

import SwiftUI
import CollegeCareer

/// A single Overview card that unifies the former Career Pipeline and Career
/// Follow-ups widgets. Showing two separate Career cards doubled the
/// "nothing here yet" signal on a fresh account, so this consolidates the
/// domain into one card: pipeline counts on top, the most urgent follow-ups
/// inline below, and a single empty-state CTA when there is no activity.
struct CareerSummaryWidget: View {
    @Environment(AppContainer.self) private var container
    private var collegePersistence: CollegePersistence { container.persistence }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dataRefreshToken = 0

    var onNavigateToCareer: (CareerApplicationStatus?) -> Void = { _ in }

    private var statusCounts: [CareerApplicationStatus: Int] {
        _ = collegePersistence.careerDidChangeToken
        _ = dataRefreshToken
        return CareerReadBridge.statusCounts() ?? [:]
    }

    private var followUps: [OverviewCareerFollowUpSummary] {
        _ = collegePersistence.careerDidChangeToken
        _ = dataRefreshToken
        return OverviewReadBridge.careerFollowUps(limit: 2, collegePersistence: collegePersistence)
    }

    private var hasActivity: Bool {
        statusCounts.values.reduce(0, +) > 0 || !followUps.isEmpty
    }

    private var accent: Color { WidgetCategory.productivity.accentColor }

    var body: some View {
        OverviewCard {
            OverviewWidgetHeader("Career", systemImage: "briefcase.fill", accentColor: accent) {
                if hasActivity {
                    Button("Open") { onNavigateToCareer(nil) }
                        .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                        .foregroundStyle(accent)
                        .buttonStyle(.plain)
                }
            }

            Color.clear.frame(height: 16)

            if hasActivity {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        metric("Applied", status: .applied, color: .blue)
                        metric("Interview", status: .interviewing, color: .purple)
                        metric("Offer", status: .offer, color: .green)
                    }
                    VStack(spacing: 10) {
                        metric("Applied", status: .applied, color: .blue)
                        metric("Interview", status: .interviewing, color: .purple)
                        metric("Offer", status: .offer, color: .green)
                    }
                }

                if !followUps.isEmpty {
                    Color.clear.frame(height: 14)
                    Text("FOLLOW-UPS")
                        .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 6)
                    VStack(spacing: 8) {
                        ForEach(followUps) { row in
                            followUpRow(row)
                        }
                    }
                }
            } else {
                Button {
                    onNavigateToCareer(nil)
                } label: {
                    OverviewWidgetEmptyState(
                        title: "Track your first application",
                        message: "Applications, interviews, and follow-ups show up here.",
                        systemImage: "briefcase",
                        accentColor: accent
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .background {
            OverviewQueryHost { dataRefreshToken += 1 }
        }
    }

    private func count(_ status: CareerApplicationStatus) -> Int {
        statusCounts[status] ?? 0
    }

    private func metric(_ title: String, status: CareerApplicationStatus, color: Color) -> some View {
        let value = count(status)
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

    private func followUpRow(_ row: OverviewCareerFollowUpSummary) -> some View {
        Button {
            onNavigateToCareer(nil)
        } label: {
            OverviewWidgetRowSurface(accentColor: accent) {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.up.message.fill")
                        .font(DesignSystem.Fonts.main(size: 13, weight: .semibold))
                        .foregroundStyle(accent)
                        .frame(width: 32, height: 32)
                        .background(accent.opacity(0.12))
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
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
    }
}

extension CareerSummaryWidget {
    static var descriptor: WidgetDescriptor {
        WidgetDescriptor(
            id: "career_summary",
            displayName: "Career Summary",
            description: "Pipeline counts and urgent follow-ups in one card.",
            category: .productivity,
            iconName: "briefcase.fill",
            accentColor: .purple,
            defaultHeight: 200,
            minHeight: 160,
            makePreview: { CareerSummaryWidget(onNavigateToCareer: { _ in }) }
        )
    }
}
