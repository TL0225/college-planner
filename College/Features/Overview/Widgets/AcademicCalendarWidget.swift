// AcademicCalendarWidget.swift
// Feature: Overview
// Purpose: Overview module — AcademicCalendarWidget.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI

struct AcademicCalendarWidget: View {
    @Environment(AppContainer.self) private var container
    private var persistence: CollegePersistence { container.persistence }
    private var collegePersistence: CollegePersistence { container.persistence }
    @State private var dataRefreshToken = 0

    private var academicProfiles: [AcademicProfile] {
        _ = collegePersistence.plannerChangeToken
        _ = dataRefreshToken
        return OverviewReadBridge.academicProfiles(collegePersistence: collegePersistence)
    }

    var body: some View {
        OverviewCard {
            OverviewWidgetHeader(
                String(localized: "widget.academic_calendar.title"),
                systemImage: "calendar",
                accentColor: WidgetCategory.academic.accentColor
            )

            Color.clear.frame(height: 16)

            if academicProfiles.isEmpty {
                OverviewWidgetEmptyState(
                    title: String(localized: "widget.academic_calendar.empty"),
                    message: String(localized: "widget.academic_calendar.empty.message", defaultValue: "Add an academic profile to track term milestones."),
                    systemImage: "calendar.badge.plus",
                    accentColor: .teal
                )
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(academicProfiles, id: \.id) { ap in
                        calendarRow(ap)
                    }
                }
            }
        }
        .background {
            OverviewQueryHost { dataRefreshToken += 1 }
        }
    }

    @ViewBuilder
    private func calendarRow(_ ap: AcademicProfile) -> some View {
        let label = ap.resolvedShortLabel(among: academicProfiles)
        let grad = ap.expectedGraduation?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        OverviewWidgetRowSurface(accentColor: ap.accentColor) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "graduationcap.fill")
                    .font(DesignSystem.Fonts.main(size: 13, weight: .semibold))
                    .foregroundStyle(ap.accentColor)
                    .frame(width: 32, height: 32)
                    .background(ap.accentColor.opacity(0.12))
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(DesignSystem.Fonts.main(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                    if !grad.isEmpty {
                        Text(String(format: String(localized: "widget.academic_calendar.graduation"), grad))
                            .font(DesignSystem.Fonts.main(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    } else {
                        Text(String(localized: "widget.academic_calendar.no_date"))
                            .font(DesignSystem.Fonts.main(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
        }
    }

    static var descriptor: WidgetDescriptor {
        WidgetDescriptor(
            id: "academic_calendar",
            displayName: String(localized: "widget.academic_calendar.title"),
            description: String(localized: "widget.academic_calendar.description"),
            category: .academic,
            iconName: "calendar",
            accentColor: .teal,
            defaultHeight: 180,
            minHeight: 140,
            makePreview: { AcademicCalendarWidgetPreview() }
        )
    }
}

private struct AcademicCalendarWidgetPreview: View {
    var body: some View {
        OverviewCard {
            Text("Academic Calendar").font(.headline)
            Text("Bachelors — Spring 2026").font(.caption)
        }
    }
}
