// AcademicCalendarWidget.swift
// Feature: Overview
// Purpose: Overview module — AcademicCalendarWidget.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI

struct AcademicCalendarWidget: View {
    @EnvironmentObject private var collegePersistence: CollegePersistence
    @State private var dataRefreshToken = 0

    private var academicProfiles: [AcademicProfile] {
        _ = collegePersistence.plannerChangeToken
        _ = dataRefreshToken
        return OverviewReadBridge.academicProfiles(collegePersistence: collegePersistence)
    }

    var body: some View {
        OverviewCard {
            Text(String(localized: "widget.academic_calendar.title"))
                .font(DesignSystem.Fonts.main(size: 16, weight: .bold, design: .serif))

            if academicProfiles.isEmpty {
                Text(String(localized: "widget.academic_calendar.empty"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(academicProfiles, id: \.id) { ap in
                        calendarRow(ap)
                    }
                }
                .padding(.top, 6)
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

        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(ap.accentColor)
                .frame(width: 6, height: 6)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                if !grad.isEmpty {
                    Text(String(format: String(localized: "widget.academic_calendar.graduation"), grad))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(String(localized: "widget.academic_calendar.no_date"))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
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
