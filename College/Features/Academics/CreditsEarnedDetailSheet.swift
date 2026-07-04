// CreditsEarnedDetailSheet.swift
// Feature: Academics
// Purpose: Academics module — CreditsEarnedDetailSheet.
// Data: CollegePersistence / repositories when applicable.

// CreditsEarnedDetailSheet.swift
// The detail sheet hosted from the compact "Credits Earned" stat card, mirroring
// the Graduation Timeline sheet's structure and motion language:
//   • A hero header (credits earned of required + stacked status progress).
//   • A status breakdown (completed / in progress / planned / remaining).
//   • A per-program breakdown (primary degree + additional majors/minors).
//   • A per-semester credit ledger with stacked mini-bars.
//   • Staggered card entrance animations + Reduce Motion support.

import CollegeAcademics
import SwiftUI

struct CreditsEarnedDetailSheet: View {
    @Environment(AppContainer.self) private var container
    private var collegePersistence: CollegePersistence { container.persistence }

    let creditsEarned: Int
    let creditsRequired: Int
    let buckets: AcademicsCreditBuckets
    let programsBreakdown: CollegePersistence.DeclaredProgramsCreditsBreakdown

    @Environment(\.dismiss) private var dismiss
    @State private var hasAnimatedIn = false

    /// Graduation-pace projector input (ephemeral — seeded from live data on first appear).
    @State private var creditsPerTerm: Int = 15
    @State private var didSeedPace = false

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage("ui.reduceMotion") private var prefReduceMotion = false
    private var motionReduced: Bool { systemReduceMotion || prefReduceMotion }

    private var contentAnimation: Animation {
        motionReduced ? .easeOut(duration: 0.12) : .spring(response: 0.34, dampingFraction: 0.86)
    }

    // MARK: - Derived data

    private var remaining: Int {
        max(0, creditsRequired - buckets.completed - buckets.inProgress - buckets.planned)
    }

    private var fractionComplete: Double {
        guard creditsRequired > 0 else { return 0 }
        return min(1, Double(buckets.completed) / Double(creditsRequired))
    }

    private struct SemesterCreditRow: Identifiable {
        let id: UUID
        let label: String
        let completed: Int
        let inProgress: Int
        let planned: Int
        var total: Int { completed + inProgress + planned }
    }

    private var orderedSemesters: [PlannerSemester] {
        let plan = collegePersistence.getActivePlan()
        let raw = plan?.semestersArray ?? collegePersistence.semesters
        return raw.sorted { lhs, rhs in
            if lhs.year != rhs.year { return lhs.year < rhs.year }
            return lhs.seasonOrder < rhs.seasonOrder
        }
    }

    private var semesterRows: [SemesterCreditRow] {
        orderedSemesters.map { semester in
            var completed = 0
            var inProgress = 0
            var planned = 0
            for course in semester.coursesArray {
                let status = course.status.trimmingCharacters(in: .whitespacesAndNewlines)
                let credits = Int(course.credits)
                if course.isCompleted || status == "Completed" {
                    completed += credits
                } else if status == "In Progress" || status == "In-Progress" {
                    inProgress += credits
                } else if status == "Planned" {
                    planned += credits
                }
            }
            return SemesterCreditRow(
                id: semester.id,
                label: semesterLabel(semester),
                completed: completed,
                inProgress: inProgress,
                planned: planned
            )
        }
    }

    private func semesterLabel(_ semester: PlannerSemester) -> String {
        let season = semester.season.trimmingCharacters(in: .whitespacesAndNewlines)
        let year = Int(semester.year)
        if season.isEmpty { return semester.name.isEmpty ? "Semester \(year)" : semester.name }
        return year > 0 ? "\(season) \(year)" : season
    }

    private var hasRequirementData: Bool { creditsRequired > 0 }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    heroHeader
                        .modifier(CreditsEntranceModifier(index: 0, isVisible: hasAnimatedIn, reduceMotion: motionReduced))
                    statusBreakdown
                        .modifier(CreditsEntranceModifier(index: 1, isVisible: hasAnimatedIn, reduceMotion: motionReduced))
                    if hasRequirementData {
                        paceProjector
                            .modifier(CreditsEntranceModifier(index: 2, isVisible: hasAnimatedIn, reduceMotion: motionReduced))
                    }
                    if programsBreakdown.hasAdditionalPrograms {
                        programBreakdown
                            .modifier(CreditsEntranceModifier(index: 3, isVisible: hasAnimatedIn, reduceMotion: motionReduced))
                    }
                    semesterLedger
                        .modifier(CreditsEntranceModifier(index: 4, isVisible: hasAnimatedIn, reduceMotion: motionReduced))
                }
                .padding(DesignSystem.Spacing.lg)
            }
            .scrollIndicators(.hidden)
        }
        .frame(
            minWidth: 560, idealWidth: 640, maxWidth: 760,
            minHeight: 640, idealHeight: 740, maxHeight: 900
        )
        .dismissOnOutsideClickForSheet()
        .onAppear {
            seedPaceIfNeeded()
            guard !hasAnimatedIn else { return }
            DispatchQueue.main.async { hasAnimatedIn = true }
        }
    }

    private func seedPaceIfNeeded() {
        guard !didSeedPace else { return }
        didSeedPace = true
        // Seed from the average load of the student's most recent non-empty terms.
        let recent = semesterRows.filter { $0.total > 0 }.suffix(3)
        if !recent.isEmpty {
            let avg = recent.reduce(0) { $0 + $1.total } / recent.count
            if avg > 0 { creditsPerTerm = max(3, min(24, avg)) }
        }
    }

    // MARK: - Title bar

    private var titleBar: some View {
        HStack {
            Button("Done") { dismiss() }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            Spacer()
            Text("Credits Earned")
                .font(DesignSystem.Fonts.main(size: 14, weight: .semibold))
            Spacer()
            Button("Done") { dismiss() }
                .buttonStyle(.plain)
                .opacity(0)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.thinMaterial)
    }

    // MARK: - Hero header

    private var heroHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text("\(buckets.completed)")
                    .font(DesignSystem.Fonts.main(size: 40, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                if hasRequirementData {
                    Text("/ \(creditsRequired) credits earned")
                        .font(DesignSystem.Fonts.main(size: 16, weight: .medium))
                        .foregroundStyle(.secondary)
                } else {
                    Text("credits earned")
                        .font(DesignSystem.Fonts.main(size: 16, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if hasRequirementData {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("COMPLETE")
                            .font(DesignSystem.Fonts.main(size: 9, weight: .bold))
                            .tracking(0.6)
                            .foregroundStyle(.secondary)
                        Text("\(Int((fractionComplete * 100).rounded()))%")
                            .font(DesignSystem.Fonts.main(size: 16, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }

            stackedProgress

            if hasRequirementData {
                Text("\(remaining) credits remaining to reach your degree total.")
                    .font(DesignSystem.Fonts.main(size: 11))
                    .foregroundStyle(.secondary)
            }
            if let footnote = programsBreakdown.optionalProgramsFootnote {
                Text(footnote)
                    .font(DesignSystem.Fonts.main(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(DesignSystem.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(DesignSystem.Colors.glassCardBase)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(DesignSystem.Colors.chromeStroke, lineWidth: 1)
        )
    }

    private var stackedProgress: some View {
        GeometryReader { geo in
            let total = max(Double(creditsRequired), Double(buckets.completed + buckets.inProgress + buckets.planned), 1.0)
            let scale = hasAnimatedIn ? 1.0 : 0.0
            let cFrac = min(Double(buckets.completed) / total, 1.0) * scale
            let iFrac = min(Double(buckets.inProgress) / total, 1.0 - cFrac) * scale
            let pFrac = min(Double(buckets.planned) / total, 1.0 - cFrac - iFrac) * scale
            let rFrac = max(0.0, 1.0 - cFrac - iFrac - pFrac)
            HStack(spacing: 2) {
                Rectangle().fill(AcademicsStatusPalette.completedDot)
                    .frame(width: geo.size.width * CGFloat(cFrac))
                Rectangle().fill(AcademicsStatusPalette.inProgressDot)
                    .frame(width: geo.size.width * CGFloat(iFrac))
                Rectangle().fill(AcademicsStatusPalette.plannedDot)
                    .frame(width: geo.size.width * CGFloat(pFrac))
                Rectangle().fill(AcademicsStatusPalette.remainingDot)
                    .frame(width: geo.size.width * CGFloat(rFrac))
            }
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .animation(motionReduced ? nil : .spring(response: 0.7, dampingFraction: 0.86), value: hasAnimatedIn)
        }
        .frame(height: 10)
    }

    // MARK: - Status breakdown

    private var statusBreakdown: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("STATUS BREAKDOWN")
            VStack(spacing: 8) {
                statusRow(state: .completed, label: "Completed", value: buckets.completed)
                statusRow(state: .inProgress, label: "In Progress", value: buckets.inProgress)
                statusRow(state: .planned, label: "Planned", value: buckets.planned)
                if hasRequirementData {
                    statusRow(state: .remaining, label: "Remaining", value: remaining)
                }
            }
        }
        .padding(DesignSystem.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(DesignSystem.Colors.glassCardBase)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(DesignSystem.Colors.chromeStroke, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func statusRow(state: AcademicsStatusPalette.State, label: String, value: Int) -> some View {
        let denom = max(1, hasRequirementData ? creditsRequired : (buckets.completed + buckets.inProgress + buckets.planned))
        let color = AcademicsStatusPalette.dot(for: state)
        HStack(spacing: 12) {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(label)
                .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                .frame(width: 96, alignment: .leading)
            GeometryReader { geo in
                let fraction = max(0, min(1, Double(value) / Double(denom)))
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.07))
                    Capsule()
                        .fill(color)
                        .frame(width: geo.size.width * CGFloat(hasAnimatedIn ? fraction : 0))
                }
                .animation(motionReduced ? nil : .spring(response: 0.6, dampingFraction: 0.86), value: hasAnimatedIn)
            }
            .frame(height: 7)
            Text("\(value) cr")
                .font(DesignSystem.Fonts.main(size: 13, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .frame(width: 52, alignment: .trailing)
        }
    }

    // MARK: - Graduation pace projector

    private var termsRemaining: Int {
        guard remaining > 0 else { return 0 }
        return Int(ceil(Double(remaining) / Double(max(1, creditsPerTerm))))
    }

    /// Upcoming Fall/Spring terms only (the standard full-time enrollment terms),
    /// starting after the current term.
    private func upcomingPrimaryTerms(_ count: Int) -> [(year: Int, season: String)] {
        guard count > 0 else { return [] }
        let current = GraduationTimelineEngine.currentTerm()
        let all = GraduationTimelineEngine.suggestTargetTerms(from: current, count: count * 3 + 6)
        let primary = all.filter { $0.season == "Fall" || $0.season == "Spring" }
        return Array(primary.prefix(count))
    }

    private var projectedFinishLabel: String? {
        guard termsRemaining > 0 else { return nil }
        guard let last = upcomingPrimaryTerms(termsRemaining).last else { return nil }
        return "\(last.season) \(last.year)"
    }

    private var paceProjector: some View {
        let done = remaining <= 0
        let color = done ? AcademicsStatusPalette.completedDot : Color.accentColor
        return VStack(alignment: .leading, spacing: 14) {
            sectionHeader("GRADUATION PACE")

            HStack(spacing: 12) {
                Text("Credits per term")
                    .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                Spacer(minLength: 8)
                Text("\(creditsPerTerm) cr")
                    .font(DesignSystem.Fonts.main(size: 18, weight: .bold))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(creditsPerTerm)))
                Stepper(
                    value: Binding(
                        get: { creditsPerTerm },
                        set: { newValue in withAnimation(contentAnimation) { creditsPerTerm = max(1, min(24, newValue)) } }
                    ),
                    in: 1...24
                ) { EmptyView() }
                    .labelsHidden()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(DesignSystem.Colors.chromeStroke, lineWidth: 1)
            )

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: done ? "checkmark.seal.fill" : "graduationcap.fill")
                    .font(DesignSystem.Fonts.main(size: 16, weight: .semibold))
                    .foregroundStyle(color)
                    .contentTransition(.symbolEffect(.replace))
                VStack(alignment: .leading, spacing: 3) {
                    if done {
                        Text("Credit goal reached")
                            .font(DesignSystem.Fonts.main(size: 13, weight: .semibold))
                        Text("You've earned all \(creditsRequired) credits required for your degree.")
                            .font(DesignSystem.Fonts.main(size: 11))
                            .foregroundStyle(.secondary)
                    } else {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("\(termsRemaining)")
                                .font(DesignSystem.Fonts.main(size: 18, weight: .bold))
                                .monospacedDigit()
                                .foregroundStyle(color)
                                .contentTransition(.numericText(value: Double(termsRemaining)))
                            Text(termsRemaining == 1 ? "more term" : "more terms")
                                .font(DesignSystem.Fonts.main(size: 13, weight: .medium))
                                .foregroundStyle(.primary)
                            if let finish = projectedFinishLabel {
                                Text("· finish by \(finish)")
                                    .font(DesignSystem.Fonts.main(size: 13, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Text("\(remaining) credits left at \(creditsPerTerm) cr per Fall/Spring term.")
                            .font(DesignSystem.Fonts.main(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(color.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(color.opacity(0.3), lineWidth: 1)
            )
        }
        .animation(contentAnimation, value: termsRemaining)
        .padding(DesignSystem.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(DesignSystem.Colors.glassCardBase)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(DesignSystem.Colors.chromeStroke, lineWidth: 1)
        )
    }

    // MARK: - Per-program breakdown

    private var programBreakdown: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("PROGRESS BY PROGRAM")
            VStack(spacing: 8) {
                programRow(
                    name: "Primary degree",
                    completed: programsBreakdown.primary.completedRoundedInt,
                    required: programsBreakdown.primary.requiredRoundedInt
                )
                ForEach(programsBreakdown.additionalPrograms) { program in
                    programRow(
                        name: program.displayName,
                        completed: program.progress.completedRoundedInt,
                        required: program.progress.requiredRoundedInt
                    )
                }
            }
        }
        .padding(DesignSystem.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(DesignSystem.Colors.glassCardBase)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(DesignSystem.Colors.chromeStroke, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func programRow(name: String, completed: Int, required: Int) -> some View {
        let fraction = required > 0 ? max(0, min(1, Double(completed) / Double(required))) : 0
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(name)
                    .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(required > 0 ? "\(completed)/\(required) cr" : "\(completed) cr")
                    .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.07))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color.accentColor.opacity(0.65), Color.accentColor],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * CGFloat(hasAnimatedIn ? fraction : 0))
                }
                .animation(motionReduced ? nil : .spring(response: 0.6, dampingFraction: 0.86), value: hasAnimatedIn)
            }
            .frame(height: 7)
        }
    }

    // MARK: - Per-semester ledger

    private var semesterLedger: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("CREDITS BY SEMESTER")
            let rows = semesterRows.filter { $0.total > 0 }
            if rows.isEmpty {
                Text("Add courses to your semesters to see a credit ledger.")
                    .font(DesignSystem.Fonts.main(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10)
            } else {
                let maxTotal = rows.map(\.total).max() ?? 1
                VStack(spacing: 6) {
                    ForEach(rows) { row in
                        semesterLedgerRow(row, maxTotal: maxTotal)
                    }
                }
            }
        }
        .padding(DesignSystem.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(DesignSystem.Colors.glassCardBase)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(DesignSystem.Colors.chromeStroke, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func semesterLedgerRow(_ row: SemesterCreditRow, maxTotal: Int) -> some View {
        HStack(spacing: 12) {
            Text(row.label)
                .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 104, alignment: .leading)
                .lineLimit(1)

            GeometryReader { geo in
                let widthFor: (Int) -> CGFloat = { value in
                    let frac = CGFloat(value) / CGFloat(max(1, maxTotal))
                    return geo.size.width * frac * (hasAnimatedIn ? 1 : 0)
                }
                HStack(spacing: 2) {
                    if row.completed > 0 {
                        Rectangle().fill(AcademicsStatusPalette.completedDot)
                            .frame(width: widthFor(row.completed))
                    }
                    if row.inProgress > 0 {
                        Rectangle().fill(AcademicsStatusPalette.inProgressDot)
                            .frame(width: widthFor(row.inProgress))
                    }
                    if row.planned > 0 {
                        Rectangle().fill(AcademicsStatusPalette.plannedDot)
                            .frame(width: widthFor(row.planned))
                    }
                    Spacer(minLength: 0)
                }
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .animation(motionReduced ? nil : .spring(response: 0.6, dampingFraction: 0.86), value: hasAnimatedIn)
            }
            .frame(height: 10)

            Text("\(row.total) cr")
                .font(DesignSystem.Fonts.main(size: 13, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .frame(width: 52, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(DesignSystem.Colors.chromeStroke, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.label): \(row.total) credits — \(row.completed) completed, \(row.inProgress) in progress, \(row.planned) planned")
    }

    // MARK: - Section header

    @ViewBuilder
    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
            .foregroundStyle(.secondary)
            .tracking(0.8)
    }
}

/// Staggered fade/slide/blur reveal mirroring the Graduation Timeline sheet.
private struct CreditsEntranceModifier: ViewModifier {
    let index: Int
    let isVisible: Bool
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? 0 : (reduceMotion ? 0 : 16))
            .blur(radius: isVisible ? 0 : (reduceMotion ? 0 : 5))
            .animation(
                reduceMotion
                    ? .easeOut(duration: 0.12)
                    : .spring(response: 0.42, dampingFraction: 0.85).delay(Double(index) * 0.07),
                value: isVisible
            )
    }
}
