// AcademicsViewSupport.swift
// Feature: Academics
// Purpose: Shared academics UI helpers (Phase 6 decomposition).

import SwiftUI
import SwiftData

enum AcademicsMotion {
    static let cardStaggerStep: Double = 0.045
    static let revealDuration: Double = 0.30
    static let reducedRevealDuration: Double = 0.10
    static let hoverDuration: Double = 0.18
}
struct AcademicsEntranceModifier: ViewModifier {
    let index: Int
    let isVisible: Bool
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            .opacity(isVisible || reduceMotion ? 1 : 0)
            .animation(CollegeMotion.standardOrNone(reduced: reduceMotion), value: isVisible)
    }
}

struct AcademicsPressableCardStyle: ButtonStyle {
    var reduceMotion: Bool = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1.0)
            .animation(.spring(response: 0.10, dampingFraction: 0.72), value: configuration.isPressed)
    }
}
// MARK: - Degree Progress Card

struct AcademicsDegreeCard: View {
    struct BarRow {
        let label: String
        let progress: CollegePersistence.CreditsProgressSummary
        let color: Color
    }

    let badge: String
    let badgeColor: Color
    let title: String
    let circleColor: Color
    let progress: CollegePersistence.CreditsProgressSummary
    let rows: [BarRow]

    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var pct: Int { Int((progress.fraction * 100).rounded()) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Title row + progress circle
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(badge)
                        .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
                        .foregroundStyle(badgeColor)
                        .tracking(0.8)
                    Text(title)
                        .font(DesignSystem.Fonts.main(size: 19, weight: .bold, design: .serif))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                // Circular progress indicator
                ZStack {
                    Circle()
                        .stroke(Color.primary.opacity(0.08), lineWidth: 6)
                    Circle()
                        .trim(from: 0, to: appeared ? CGFloat(progress.fraction) : 0)
                        .stroke(circleColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(pct)%")
                        .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .frame(width: 48, height: 48)
                .animation(.spring(response: 0.7, dampingFraction: 0.84), value: appeared)
            }

            Spacer(minLength: 0)

            // Progress bars
            VStack(spacing: 10) {
                ForEach(rows.indices, id: \.self) { i in
                    let row = rows[i]
                    VStack(spacing: 4) {
                        HStack {
                            Text(row.label)
                                .font(DesignSystem.Fonts.main(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Spacer()
                            Text(
                                row.progress.requiredRoundedInt > 0
                                    ? "\(row.progress.completedRoundedInt)/\(row.progress.requiredRoundedInt) Cr"
                                    : "\(row.progress.completedRoundedInt) Cr"
                            )
                                .font(DesignSystem.Fonts.main(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.primary.opacity(0.08))
                                    .frame(height: 6)
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(row.color)
                                    .frame(
                                        width: appeared ? max(0, geo.size.width * CGFloat(row.progress.fraction)) : 0,
                                        height: 6
                                    )
                                    .animation(.spring(response: 0.7, dampingFraction: 0.84), value: appeared)
                            }
                        }
                        .frame(height: 6)
                    }
                }
            }
        }
        .padding(DesignSystem.Spacing.lg)
        .frame(maxWidth: .infinity, minHeight: 160, alignment: .topLeading)
        .background(DesignSystem.Colors.glassCardBase.background(.thinMaterial))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(DesignSystem.Colors.chromeStroke, lineWidth: 1)
        )
        .pointerStyle(.link)
        .onAppear {
            guard !appeared else { return }
            withAnimation(.spring(response: 0.7, dampingFraction: 0.84).delay(0.1)) {
                appeared = true
            }
        }
    }
}

// MARK: - Semester row ↔ requirement breakdown (shared rules)

/// Progress for a single requirement course row, derived from planner courses matching that code.
enum RequirementPlanProgress: Int, Comparable, Equatable {
    /// No matching course on any semester.
    case notOnPlan = 0
    /// On a semester but not active / not finished (draft, future term, etc.).
    case planned = 1
    case inProgress = 2
    case completed = 3

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Keeps `AcademicsCourseRow` and the requirements breakdown on the same completion rules.
enum AcademicsCourseSchedule {
    static func semesterHasEnded(_ course: PlannerCourse, asOf today: Date = Date()) -> Bool {
        guard let sem = course.semester else { return false }
        let yr = Int(sem.year)
        let month: Int
        switch sem.season.lowercased() {
        case "winter": month = 1
        case "spring": month = 5
        case "summer": month = 8
        default:       month = 12
        }
        let end = Calendar.current.date(from: DateComponents(year: yr, month: month, day: 28)) ?? .distantPast
        return end < today
    }

    /// Same string the semester card shows as status (including past-term “Completed” override).
    static func displayStatus(course: PlannerCourse, asOf today: Date = Date()) -> String {
        let status = course.status.isEmpty ? "Draft" : course.status
        if semesterHasEnded(course, asOf: today), !status.lowercased().contains("complet") {
            return "Completed"
        }
        return status
    }

    /// Counts for degree requirement math and green checkmarks — not just the `isCompleted` local store flag.
    static func countsTowardRequirementCompletion(_ course: PlannerCourse, asOf today: Date = Date()) -> Bool {
        if course.isCompleted { return true }
        let shown = displayStatus(course: course, asOf: today).lowercased()
        if shown.contains("incomplete") { return false }
        if shown.contains("complet") { return true }
        return false
    }

    static func singleCoursePlanProgress(_ course: PlannerCourse, asOf today: Date = Date()) -> RequirementPlanProgress {
        if countsTowardRequirementCompletion(course, asOf: today) { return .completed }
        let raw = course.status.lowercased()
        if raw.contains("enroll") || raw.contains("in progress") || raw.contains("registered") { return .inProgress }
        if raw.contains("waitlist") { return .inProgress }
        return .planned
    }

    static func mergeProgress(_ a: RequirementPlanProgress?, _ b: RequirementPlanProgress) -> RequirementPlanProgress {
        Swift.max(a ?? .notOnPlan, b)
    }
}
