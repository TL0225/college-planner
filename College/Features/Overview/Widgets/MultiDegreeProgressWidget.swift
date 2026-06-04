// MultiDegreeProgressWidget.swift
// Feature: Overview
// Purpose: Overview module — MultiDegreeProgressWidget.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI

struct MultiDegreeProgressWidget: View {
    @EnvironmentObject private var collegePersistence: CollegePersistence
    @State private var dataRefreshToken = 0

    private var academicProfiles: [AcademicProfile] {
        _ = collegePersistence.plannerChangeToken
        _ = dataRefreshToken
        return OverviewReadBridge.academicProfiles(collegePersistence: collegePersistence)
    }

    var body: some View {
        OverviewCard {
            Text(String(localized: "widget.multi_degree_progress.title"))
                .font(DesignSystem.Fonts.main(size: 16, weight: .bold, design: .serif))

            if academicProfiles.isEmpty {
                Text(String(localized: "widget.multi_degree_progress.empty"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(academicProfiles, id: \.id) { ap in
                        degreeRow(ap)
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
    private func degreeRow(_ ap: AcademicProfile) -> some View {
        let label = ap.resolvedShortLabel(among: academicProfiles)
        let progress = collegePersistence.academicProfileAggregateCreditsProgress(for: ap)
        let gpa = ap.gpa ?? 0

        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .stroke(ap.accentColor.opacity(0.2), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: min(max(progress.fraction, 0), 1))
                    .stroke(ap.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(DesignSystem.Fonts.main(size: 13, weight: .semibold))
                Text("\(progress.creditsFractionText) credits")
                    .monospacedDigit()
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if gpa > 0 {
                Text(GPAFormatting.labeledFractionText(gpa: gpa))
                    .monospacedDigit()
                    .font(DesignSystem.Fonts.main(size: 13, weight: .bold))
                    .monospacedDigit()
            }
        }
    }

    static var descriptor: WidgetDescriptor {
        WidgetDescriptor(
            id: "multi_degree_progress",
            displayName: String(localized: "widget.multi_degree_progress.title"),
            description: String(localized: "widget.multi_degree_progress.description"),
            category: .academic,
            iconName: "graduationcap.fill",
            accentColor: .blue,
            defaultHeight: 200,
            minHeight: 160,
            makePreview: { MultiDegreeProgressWidgetPreview() }
        )
    }
}

private struct MultiDegreeProgressWidgetPreview: View {
    var body: some View {
        OverviewCard {
            Text("Degrees").font(.headline)
            Text("Bachelors · 72%").font(.caption)
            Text("Masters · 18%").font(.caption)
        }
    }
}
