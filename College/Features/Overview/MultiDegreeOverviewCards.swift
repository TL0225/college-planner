// MultiDegreeOverviewCards.swift
// Feature: Overview
// Purpose: Overview module — AllDegreesProgressCard.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI

// MARK: - All degrees progress ribbon

struct AllDegreesProgressCard: View {
    let profiles: [AcademicProfile]
    var onSelect: (UUID) -> Void

    @EnvironmentObject private var collegePersistence: CollegePersistence

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(String(localized: "overview.degrees.progress.title"))
                .font(DesignSystem.Fonts.caption2())
                .foregroundStyle(.tertiary)
                .kerning(1)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(profiles, id: \.id) { ap in
                        degreeMiniCard(ap, id: ap.id)
                    }
                }
            }
        }
        .cardSurface(padding: 20)
    }

    @ViewBuilder
    private func degreeMiniCard(_ ap: AcademicProfile, id: UUID) -> some View {
        let label = ap.resolvedShortLabel(among: profiles)
        let progress = collegePersistence.academicProfileAggregateCreditsProgress(for: ap)

        Button {
            onSelect(id)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Text(label)
                    .font(DesignSystem.Fonts.headline())
                    .foregroundStyle(.primary)
                Text(String(format: "%.0f%%", progress.fraction * 100))
                    .font(DesignSystem.Fonts.main(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(ap.accentColor)
                Text(progress.creditsFractionWithSuffixText)
                    .font(DesignSystem.Fonts.caption1())
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(14)
            .frame(minWidth: 120)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Radius.md, style: .continuous)
                    .fill(ap.accentColor.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.Radius.md, style: .continuous)
                    .strokeBorder(ap.accentColor.opacity(0.35), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Career timeline (Gantt-style)

struct AcademicCareerTimelineCard: View {
    let profiles: [AcademicProfile]
    var onSelect: (UUID) -> Void
    var onAddDegree: () -> Void = {}

    private var timelineRange: (start: Date, end: Date)? {
        var dates: [Date] = []
        let cal = Calendar.current
        let now = Date()
        for ap in profiles {
            if let s = ap.startedAt { dates.append(s) }
            if let c = ap.completedAt { dates.append(c) }
            if let grad = parseGraduationDate(ap.expectedGraduation) { dates.append(grad) }
        }
        dates.append(now)
        guard let minD = dates.min(), let maxD = dates.max(), minD < maxD else { return nil }
        let pad = cal.date(byAdding: .year, value: -1, to: minD) ?? minD
        let padEnd = cal.date(byAdding: .year, value: 1, to: maxD) ?? maxD
        return (pad, padEnd)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "overview.degrees.timeline.title"))
                .font(DesignSystem.Fonts.caption2())
                .foregroundStyle(.tertiary)
                .kerning(1)

            if let range = timelineRange {
                GeometryReader { geo in
                    let width = geo.size.width
                    ZStack(alignment: .leading) {
                        ForEach(profiles, id: \.id) { ap in
                            let bar = barFrame(for: ap, range: range, width: width)
                            if let bar {
                                Button {
                                    onSelect(ap.id)
                                } label: {
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(ap.accentColor.opacity(0.75))
                                        .frame(width: bar.width, height: 14)
                                        .offset(x: bar.x)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(ap.resolvedShortLabel(among: profiles))
                            }
                        }

                        ghostFutureChapterBar(range: range, width: width)

                        let todayX = xPosition(for: Date(), range: range, width: width)
                        Rectangle()
                            .fill(Color.primary.opacity(0.35))
                            .frame(width: 1.5, height: 22)
                            .offset(x: todayX)
                    }
                    .frame(height: 22)
                }
                .frame(height: 28)

                HStack {
                    ForEach(profiles, id: \.id) { ap in
                        HStack(spacing: 4) {
                            Circle().fill(ap.accentColor).frame(width: 6, height: 6)
                            Text(ap.resolvedShortLabel(among: profiles))
                                .font(DesignSystem.Fonts.caption1())
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button(action: onAddDegree) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus.circle.fill")
                                .font(DesignSystem.Fonts.caption1())
                            Text(String(localized: "overview.degrees.timeline.add", defaultValue: "Add degree"))
                                .font(DesignSystem.Fonts.caption1())
                        }
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                VStack(spacing: DesignSystem.Spacing.sm) {
                    Text(String(localized: "overview.degrees.timeline.empty"))
                        .font(DesignSystem.Fonts.body())
                        .foregroundStyle(.secondary)
                    Button(action: onAddDegree) {
                        Text(String(localized: "overview.degrees.timeline.add_dates", defaultValue: "Add dates in Profile"))
                            .font(DesignSystem.Fonts.headline())
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .cardSurface(padding: 20)
    }

    @ViewBuilder
    private func ghostFutureChapterBar(range: (start: Date, end: Date), width: CGFloat) -> some View {
        let ghostX = width * 0.82
        Button(action: onAddDegree) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                .foregroundStyle(Color.secondary.opacity(0.5))
                .frame(width: max(width * 0.12, 28), height: 14)
                .overlay {
                    Image(systemName: "plus")
                        .font(DesignSystem.Fonts.caption2())
                        .foregroundStyle(.secondary)
                }
                .offset(x: ghostX)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add future degree chapter")
    }

    private struct BarFrame {
        let x: CGFloat
        let width: CGFloat
    }

    private func barFrame(for ap: AcademicProfile, range: (start: Date, end: Date), width: CGFloat) -> BarFrame? {
        let start = ap.startedAt ?? range.start
        let end = ap.completedAt ?? parseGraduationDate(ap.expectedGraduation) ?? Date()
        guard end > start else { return nil }
        let x0 = xPosition(for: start, range: range, width: width)
        let x1 = xPosition(for: end, range: range, width: width)
        return BarFrame(x: x0, width: max(x1 - x0, 12))
    }

    private func xPosition(for date: Date, range: (start: Date, end: Date), width: CGFloat) -> CGFloat {
        let total = range.end.timeIntervalSince(range.start)
        guard total > 0 else { return 0 }
        let t = date.timeIntervalSince(range.start) / total
        return CGFloat(min(max(t, 0), 1)) * width
    }

    private func parseGraduationDate(_ raw: String?) -> Date? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        let parts = raw.split(separator: " ")
        guard parts.count >= 2, let year = Int(parts.last ?? "") else { return nil }
        var comps = DateComponents()
        comps.year = year
        comps.month = raw.lowercased().contains("fall") ? 5 : 12
        comps.day = 15
        return Calendar.current.date(from: comps)
    }
}
