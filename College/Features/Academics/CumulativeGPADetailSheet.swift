// CumulativeGPADetailSheet.swift
// Feature: Academics
// Purpose: Academics module — CumulativeGPADetailSheet.
// Data: CollegePersistence / repositories when applicable.

// CumulativeGPADetailSheet.swift
// The detail sheet hosted from the compact "Cumulative GPA" stat card, mirroring
// the Graduation Timeline sheet's structure and motion language:
//   • A hero header (large cumulative GPA + position on the 0–4 scale).
//   • A per-semester GPA breakdown with inline bars + status colors.
//   • A grade distribution histogram across all GPA-counted courses.
//   • Staggered card entrance animations + Reduce Motion support.

import SwiftUI

struct CumulativeGPADetailSheet: View {
    @Environment(AppContainer.self) private var container
    private var collegePersistence: CollegePersistence { container.persistence }
    let academicProfile: AcademicProfile?

    @Environment(\.dismiss) private var dismiss
    @State private var hasAnimatedIn = false

    /// What-if projector inputs (ephemeral — seeded from live data on first appear).
    @State private var targetGPA: Double = 3.5
    @State private var futureCredits: Int = 15
    @State private var didSeedProjector = false

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage("ui.reduceMotion") private var prefReduceMotion = false
    private var motionReduced: Bool { systemReduceMotion || prefReduceMotion }

    private var contentAnimation: Animation {
        motionReduced ? .easeOut(duration: 0.12) : .spring(response: 0.34, dampingFraction: 0.86)
    }

    private static let gpaScaleMax = 4.0

    // MARK: - Data

    private var gradeMapping: [String: Double] {
        GPAGradeScaleStore(universityID: nil).gradePointsMapping
    }

    /// Chronologically-ordered semesters (oldest → newest) so the trend reads left-to-right.
    private var orderedSemesters: [PlannerSemester] {
        let plan = collegePersistence.getActivePlan()
        let raw = plan?.semestersArray ?? collegePersistence.semesters
        return raw.sorted { lhs, rhs in
            if lhs.year != rhs.year { return lhs.year < rhs.year }
            return lhs.seasonOrder < rhs.seasonOrder
        }
    }

    private func isLetterGraded(_ course: PlannerCourse) -> Bool {
        collegePersistence.isLetterGradedForGPA(course.gradingType.isEmpty ? nil : course.gradingType)
    }

    private var cumulative: GPACalculationResult? {
        GPACalculation.cumulativeGPA(
            semesters: orderedSemesters,
            mapping: gradeMapping,
            isLetterGradedForGPA: isLetterGraded
        )
    }

    private struct SemesterGPARow: Identifiable {
        let id: UUID
        let label: String
        let gpa: Double?
        let creditsCounted: Int
        let coursesCounted: Int
    }

    private var semesterRows: [SemesterGPARow] {
        orderedSemesters.map { semester in
            let result = GPACalculation.cumulativeGPA(
                semesters: [semester],
                mapping: gradeMapping,
                isLetterGradedForGPA: isLetterGraded
            )
            return SemesterGPARow(
                id: semester.id,
                label: semesterLabel(semester),
                gpa: result?.gpa,
                creditsCounted: result?.creditsCounted ?? 0,
                coursesCounted: result?.coursesCounted ?? 0
            )
        }
    }

    private struct GradeBar: Identifiable {
        let id = UUID()
        let grade: String
        let points: Double
        let count: Int
    }

    private var gradeDistribution: [GradeBar] {
        var counts: [String: Int] = [:]
        for semester in orderedSemesters {
            for course in semester.coursesArray where course.isCompleted {
                guard isLetterGraded(course) else { continue }
                let g = (course.grade ?? "")
                    .replacingOccurrences(of: " ", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .uppercased()
                guard !g.isEmpty, gradeMapping[g] != nil else { continue }
                counts[g, default: 0] += 1
            }
        }
        return counts
            .map { GradeBar(grade: $0.key, points: gradeMapping[$0.key] ?? 0, count: $0.value) }
            .sorted { lhs, rhs in
                if lhs.points != rhs.points { return lhs.points > rhs.points }
                return lhs.grade < rhs.grade
            }
    }

    private func semesterLabel(_ semester: PlannerSemester) -> String {
        let season = semester.season.trimmingCharacters(in: .whitespacesAndNewlines)
        let year = Int(semester.year)
        if season.isEmpty { return semester.name.isEmpty ? "Semester \(year)" : semester.name }
        return year > 0 ? "\(season) \(year)" : season
    }

    private var hasData: Bool { cumulative != nil }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            Divider()
            if hasData {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        heroHeader
                            .modifier(GPAEntranceModifier(index: 0, isVisible: hasAnimatedIn, reduceMotion: motionReduced))
                        projectorCard
                            .modifier(GPAEntranceModifier(index: 1, isVisible: hasAnimatedIn, reduceMotion: motionReduced))
                        semesterBreakdown
                            .modifier(GPAEntranceModifier(index: 2, isVisible: hasAnimatedIn, reduceMotion: motionReduced))
                        distributionCard
                            .modifier(GPAEntranceModifier(index: 3, isVisible: hasAnimatedIn, reduceMotion: motionReduced))
                    }
                    .padding(DesignSystem.Spacing.lg)
                }
                .scrollIndicators(.hidden)
            } else {
                emptyState
                    .modifier(GPAEntranceModifier(index: 0, isVisible: hasAnimatedIn, reduceMotion: motionReduced))
            }
        }
        .frame(
            minWidth: 560, idealWidth: 640, maxWidth: 760,
            minHeight: 640, idealHeight: 740, maxHeight: 900
        )
        .dismissOnOutsideClickForSheet()
        .onAppear {
            seedProjectorIfNeeded()
            guard !hasAnimatedIn else { return }
            DispatchQueue.main.async { hasAnimatedIn = true }
        }
    }

    private func seedProjectorIfNeeded() {
        guard !didSeedProjector else { return }
        didSeedProjector = true
        let current = cumulative?.gpa ?? 0
        // Default target a touch above the current GPA, rounded to 0.05, capped at 4.0.
        let bumped = (current + 0.1)
        let rounded = (bumped / 0.05).rounded() * 0.05
        targetGPA = min(4.0, max(2.0, rounded == 0 ? 3.5 : rounded))
    }

    // MARK: - Title bar

    private var titleBar: some View {
        HStack {
            Button("Done") { dismiss() }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            Spacer()
            Text("Cumulative GPA")
                .font(DesignSystem.Fonts.main(size: 14, weight: .semibold))
            Spacer()
            // Symmetry spacer so the title stays centered.
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
        let gpa = cumulative?.gpa ?? 0
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text(String(format: "%.2f", gpa))
                    .font(DesignSystem.Fonts.main(size: 40, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                Text("/ 4.00")
                    .font(DesignSystem.Fonts.main(size: 16, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text("COUNTED")
                        .font(DesignSystem.Fonts.main(size: 9, weight: .bold))
                        .tracking(0.6)
                        .foregroundStyle(.secondary)
                    Text("\(cumulative?.creditsCounted ?? 0) cr · \(cumulative?.coursesCounted ?? 0) courses")
                        .font(DesignSystem.Fonts.main(size: 13, weight: .semibold))
                        .monospacedDigit()
                }
            }

            gpaScaleBar(gpa: gpa)

            Text(standingDescription(for: gpa))
                .font(DesignSystem.Fonts.main(size: 11))
                .foregroundStyle(.secondary)
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

    private func gpaScaleBar(gpa: Double) -> some View {
        GeometryReader { geo in
            let fraction = max(0, min(1, gpa / Self.gpaScaleMax))
            let markerX = geo.size.width * CGFloat(hasAnimatedIn ? fraction : 0)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                AcademicsStatusPalette.remainingDot.opacity(0.5),
                                AcademicsStatusPalette.inProgressDot.opacity(0.7),
                                AcademicsStatusPalette.completedDot,
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 8)
                Circle()
                    .fill(.white)
                    .frame(width: 16, height: 16)
                    .overlay(Circle().stroke(Color.accentColor, lineWidth: 3))
                    .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
                    .offset(x: max(0, markerX - 8))
            }
            .frame(height: 16)
            .animation(motionReduced ? nil : .spring(response: 0.7, dampingFraction: 0.84), value: hasAnimatedIn)
        }
        .frame(height: 16)
    }

    private func standingDescription(for gpa: Double) -> String {
        switch gpa {
        case 3.9...: return "Outstanding — top of the class standing."
        case 3.5..<3.9: return "Excellent — comfortably on the Dean's List range."
        case 3.0..<3.5: return "Solid — a strong, healthy academic standing."
        case 2.0..<3.0: return "Satisfactory — meets typical good-standing minimums."
        default: return "Below the usual good-standing threshold — worth a check-in with your advisor."
        }
    }

    // MARK: - GPA goal projector

    private var currentQualityPoints: Double {
        (cumulative?.gpa ?? 0) * Double(cumulative?.creditsCounted ?? 0)
    }

    private var currentCreditsCounted: Int { cumulative?.creditsCounted ?? 0 }

    /// Average grade-point the student must earn over `futureCredits` to reach `targetGPA`.
    private var neededAverage: Double {
        guard futureCredits > 0 else { return 0 }
        let totalCredits = Double(currentCreditsCounted + futureCredits)
        return (targetGPA * totalCredits - currentQualityPoints) / Double(futureCredits)
    }

    private var projectionAlreadyMet: Bool { neededAverage <= 0.0001 }
    private var projectionFeasible: Bool { neededAverage <= 4.0001 }

    private var projectorCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("GPA GOAL PROJECTOR")

            HStack(spacing: 12) {
                projectorStat(
                    label: "TARGET GPA",
                    control: AnyView(
                        Stepper(
                            value: Binding(
                                get: { targetGPA },
                                set: { newValue in withAnimation(contentAnimation) { targetGPA = min(4.0, max(0, (newValue / 0.05).rounded() * 0.05)) } }
                            ),
                            in: 0...4, step: 0.05
                        ) {
                            Text(String(format: "%.2f", targetGPA))
                                .font(DesignSystem.Fonts.main(size: 20, weight: .bold))
                                .monospacedDigit()
                                .contentTransition(.numericText(value: targetGPA))
                        }
                        .labelsHidden()
                    ),
                    valueText: String(format: "%.2f", targetGPA)
                )
                projectorStat(
                    label: "OVER NEXT",
                    control: AnyView(
                        Stepper(
                            value: Binding(
                                get: { futureCredits },
                                set: { newValue in withAnimation(contentAnimation) { futureCredits = max(1, min(120, newValue)) } }
                            ),
                            in: 1...120, step: 3
                        ) {
                            Text("\(futureCredits) cr")
                                .font(DesignSystem.Fonts.main(size: 20, weight: .bold))
                                .monospacedDigit()
                                .contentTransition(.numericText(value: Double(futureCredits)))
                        }
                        .labelsHidden()
                    ),
                    valueText: "\(futureCredits) cr"
                )
            }

            projectionResult
        }
        .animation(contentAnimation, value: neededAverage)
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
    private func projectorStat(label: String, control: AnyView, valueText: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(DesignSystem.Fonts.main(size: 9, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Text(valueText)
                    .font(DesignSystem.Fonts.main(size: 20, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
                control
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(DesignSystem.Colors.chromeStroke, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var projectionResult: some View {
        let color: Color = projectionAlreadyMet
            ? AcademicsStatusPalette.completedDot
            : (projectionFeasible ? AcademicsStatusPalette.inProgressDot : Color.red)
        let symbol = projectionAlreadyMet
            ? "checkmark.circle.fill"
            : (projectionFeasible ? "target" : "exclamationmark.triangle.fill")

        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(DesignSystem.Fonts.main(size: 16, weight: .semibold))
                .foregroundStyle(color)
                .contentTransition(.symbolEffect(.replace))
            VStack(alignment: .leading, spacing: 3) {
                if projectionAlreadyMet {
                    Text("You're already at or above \(String(format: "%.2f", targetGPA))")
                        .font(DesignSystem.Fonts.main(size: 13, weight: .semibold))
                    Text("Any passing grades over the next \(futureCredits) cr keep you on target.")
                        .font(DesignSystem.Fonts.main(size: 11))
                        .foregroundStyle(.secondary)
                } else if projectionFeasible {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(String(format: "%.2f", neededAverage))
                            .font(DesignSystem.Fonts.main(size: 18, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(color)
                            .contentTransition(.numericText(value: neededAverage))
                        Text("avg needed (\(letterEstimate(neededAverage)))")
                            .font(DesignSystem.Fonts.main(size: 13, weight: .medium))
                            .foregroundStyle(.primary)
                    }
                    Text("Average this over your next \(futureCredits) cr to reach a \(String(format: "%.2f", targetGPA)) cumulative GPA.")
                        .font(DesignSystem.Fonts.main(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Not reachable in \(futureCredits) cr")
                        .font(DesignSystem.Fonts.main(size: 13, weight: .semibold))
                    Text("A \(String(format: "%.2f", targetGPA)) cumulative GPA would need a \(String(format: "%.2f", neededAverage)) average — above the 4.00 max. Add more credits or lower the target.")
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

    /// Rough letter-grade label for a grade-point average, using the standard 4.0 anchors.
    private func letterEstimate(_ points: Double) -> String {
        switch points {
        case 3.85...: return "≈ A"
        case 3.5..<3.85: return "≈ A-"
        case 3.15..<3.5: return "≈ B+"
        case 2.85..<3.15: return "≈ B"
        case 2.5..<2.85: return "≈ B-"
        case 2.15..<2.5: return "≈ C+"
        case 1.85..<2.15: return "≈ C"
        case 1.0..<1.85: return "≈ D"
        default: return "≈ F"
        }
    }

    // MARK: - Per-semester breakdown

    private var semesterBreakdown: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("GPA BY SEMESTER")
            let rows = semesterRows.filter { $0.coursesCounted > 0 }
            if rows.isEmpty {
                Text("No graded semesters yet.")
                    .font(DesignSystem.Fonts.main(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10)
            } else {
                VStack(spacing: 6) {
                    ForEach(rows) { row in
                        semesterRowView(row)
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
    private func semesterRowView(_ row: SemesterGPARow) -> some View {
        let gpa = row.gpa ?? 0
        let color = gpaColor(gpa)
        HStack(spacing: 12) {
            Text(row.label)
                .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 104, alignment: .leading)
                .lineLimit(1)

            GeometryReader { geo in
                let fraction = max(0, min(1, gpa / Self.gpaScaleMax))
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.07))
                    Capsule()
                        .fill(color)
                        .frame(width: geo.size.width * CGFloat(hasAnimatedIn ? fraction : 0))
                }
                .animation(motionReduced ? nil : .spring(response: 0.6, dampingFraction: 0.86), value: hasAnimatedIn)
            }
            .frame(height: 7)

            Text(String(format: "%.2f", gpa))
                .font(DesignSystem.Fonts.main(size: 13, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(color)
                .frame(width: 44, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(color.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(color.opacity(0.28), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.label): \(String(format: "%.2f", gpa)) GPA over \(row.creditsCounted) credits")
    }

    private func gpaColor(_ gpa: Double) -> Color {
        switch gpa {
        case 3.5...: return AcademicsStatusPalette.completedDot
        case 2.5..<3.5: return AcademicsStatusPalette.inProgressDot
        default: return AcademicsStatusPalette.remainingDot
        }
    }

    // MARK: - Grade distribution

    private var distributionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("GRADE DISTRIBUTION")
            let bars = gradeDistribution
            if bars.isEmpty {
                Text("No graded courses to chart yet.")
                    .font(DesignSystem.Fonts.main(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10)
            } else {
                let maxCount = bars.map(\.count).max() ?? 1
                VStack(spacing: 7) {
                    ForEach(bars) { bar in
                        HStack(spacing: 10) {
                            Text(bar.grade)
                                .font(DesignSystem.Fonts.main(size: 12, weight: .bold))
                                .monospacedDigit()
                                .frame(width: 34, alignment: .leading)
                            GeometryReader { geo in
                                let fraction = CGFloat(bar.count) / CGFloat(max(1, maxCount))
                                Capsule()
                                    .fill(gpaColor(bar.points))
                                    .frame(width: max(6, geo.size.width * (hasAnimatedIn ? fraction : 0)))
                                    .animation(motionReduced ? nil : .spring(response: 0.6, dampingFraction: 0.86), value: hasAnimatedIn)
                            }
                            .frame(height: 14)
                            Text("\(bar.count)")
                                .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(width: 28, alignment: .trailing)
                        }
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

    // MARK: - Empty state

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No GPA yet", systemImage: "chart.bar.xaxis")
        } description: {
            Text("Mark courses as completed with letter grades to start tracking your cumulative GPA. Pass/fail and in-progress courses don't count toward the GPA.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(DesignSystem.Spacing.xl)
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
private struct GPAEntranceModifier: ViewModifier {
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
