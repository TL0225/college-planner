// AcademicsLeftStatsSidebar.swift
// Feature: Academics
// Purpose: Academics module — AcademicsLeftStatsSidebar.
// Data: CollegePersistence / repositories when applicable.

// AcademicsLeftStatsSidebar.swift
// The narrow stats column on the left of the redesigned Academics page. Stacks
// the major header, requirement-progress donut, compact Graduation Timeline
// card (tap target for the configuration sheet built in Phase B), GPA + Credits
// Earned mini cards, the existing 4-segment stacked bar, and a vertical
// semester list with the Add Semester button.
//
// Designed as small private atoms in a single file so the whole left column
// stays self-contained and easy to read. Independent vertical scroll axis from
// the right canvas.

import SwiftUI
import SwiftData

// MARK: - Top-level sidebar

struct AcademicsLeftStatsSidebar: View {
    let profile: Profile?
    let academicProfile: AcademicProfile?
    let plannerGPAFormatted: String
    let plannerCreditsEarned: Int
    let plannerCreditsRequired: Int
    let programsBreakdown: CollegePersistence.DeclaredProgramsCreditsBreakdown
    let sapStats: (attempted: Int, completed: Int, rate: Double)
    let majors: [String]
    let minors: [String]

    /// Tap-through bindings hosted on `AcademicsView`. The card flips
    /// `showGraduationSheet`; the sheet itself is presented from the parent.
    @Binding var showGraduationSheet: Bool

    @EnvironmentObject private var collegePersistence: CollegePersistence
    @Environment(ModalCoordinator.self) private var modalCoordinator

    private var primaryMajor: String {
        majors.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// First major's requirement-progress summary. The Figma's hero donut tracks
    /// this number — completed credits earned toward the primary major's required
    /// total. Multi-major students will still see the aggregate elsewhere
    /// (Graduation Timeline card + bottom strip).
    private var primaryMajorProgress: CollegePersistence.CreditsProgressSummary {
        guard !primaryMajor.isEmpty else {
            return CollegePersistence.CreditsProgressSummary(completed: 0, required: 0, fraction: 0)
        }
        if let academicProfile {
            return collegePersistence.majorRequirementsCreditsProgress(
                forMajorDisplay: primaryMajor,
                academicProfile: academicProfile
            )
        }
        return collegePersistence.majorRequirementsCreditsProgress(forMajorDisplay: primaryMajor)
    }

    private var expectedGraduation: String? {
        let raw = (academicProfile?.expectedGraduation
            ?? collegePersistence.primaryExpectedGraduation()
            ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.isEmpty ? nil : raw
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                MajorHeaderRow(index: 1, name: primaryMajor)
                RequirementProgressCard(progress: primaryMajorProgress)
                CompactGraduationTimelineCard(
                    completedCredits: plannerCreditsEarned,
                    requiredCredits: plannerCreditsRequired,
                    programsBreakdown: programsBreakdown,
                    expectedGraduation: expectedGraduation,
                    showSheet: $showGraduationSheet
                )
                if let prof = profile {
                    MiniStatGridRow(
                        gpaText: plannerGPAFormatted,
                        creditsEarned: plannerCreditsEarned,
                        creditsRequired: plannerCreditsRequired,
                        programsBreakdown: programsBreakdown
                    )
                    StackedProgressLegendBlock(
                        profile: prof,
                        sapStats: sapStats,
                        graduationCreditsRequired: plannerCreditsRequired,
                        programsBreakdown: programsBreakdown
                    )
                }
                SemesterListCompact()
                AddSemesterButton {
                    modalCoordinator.activeModal = .addSemester
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 16)
        }
        .frame(maxHeight: .infinity)
        .background(DesignSystem.Colors.surface)
    }
}

// MARK: - Major header

private struct MajorHeaderRow: View {
    let index: Int
    let name: String

    private var displayName: String {
        name.isEmpty ? String(localized: "academics.sidebar.no_major", defaultValue: "Add Your Major") : name
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(index == 1 ? "DEGREE" : "MAJOR \(index)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .tracking(0.8)
                Text(displayName)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            // Static three-dot glyph (no menu in v1, per design decision).
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.tertiary)
                .padding(.top, 6)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Requirement progress donut card

private struct RequirementProgressCard: View {
    let progress: CollegePersistence.CreditsProgressSummary

    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var pct: Int { Int((progress.fraction * 100).rounded()) }

    private var creditsLine: String {
        let req = progress.requiredRoundedInt
        let done = progress.completedRoundedInt
        if req <= 0 { return "\(done) cr toward requirement" }
        return "\(done)/\(req) cr toward requirement"
    }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.08), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: appeared ? CGFloat(progress.fraction) : 0)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(pct)%")
                    .font(.system(size: 13, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
            }
            .frame(width: 56, height: 56)
            .animation(.spring(response: 0.7, dampingFraction: 0.84), value: appeared)

            VStack(alignment: .leading, spacing: 2) {
                Text("Requirement progress")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(creditsLine)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.accentColor)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(DesignSystem.Colors.glassCardBase)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(DesignSystem.Colors.chromeStroke, lineWidth: 1)
        )
        .onAppear {
            guard !appeared else { return }
            if reduceMotion {
                appeared = true
            } else {
                withAnimation(.spring(response: 0.7, dampingFraction: 0.84).delay(0.1)) {
                    appeared = true
                }
            }
        }
    }
}

// MARK: - Compact Graduation Timeline card (tap target for the Phase B sheet)

struct CompactGraduationTimelineCard: View {
    let completedCredits: Int
    let requiredCredits: Int
    let programsBreakdown: CollegePersistence.DeclaredProgramsCreditsBreakdown
    let expectedGraduation: String?
    @Binding var showSheet: Bool

    private var fraction: Double {
        guard requiredCredits > 0 else { return 0 }
        return min(1.0, Double(completedCredits) / Double(requiredCredits))
    }

    private var timelineSubtitle: String {
        if programsBreakdown.hasAdditionalPrograms {
            return String(
                localized: "academics.graduation.timeline.degree_only",
                defaultValue: "Degree requirement — additional majors and minors tracked separately"
            )
        }
        return String(
            localized: "academics.graduation.timeline.single_program",
            defaultValue: "Progress toward your degree requirement"
        )
    }

    var body: some View {
        Button {
            showSheet = true
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "graduationcap.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 34, height: 34)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(Color.accentColor.opacity(0.12))
                        )

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("Graduation Timeline")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            if let chip = expectedGraduation, !chip.isEmpty {
                                Text(chip.uppercased())
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(
                                        Capsule().fill(Color.secondary.opacity(0.12))
                                    )
                            }
                        }
                        Text(timelineSubtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 6)
                }

                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(
                            programsBreakdown.hasAdditionalPrograms
                                ? String(localized: "academics.graduation.degree_credit_progress", defaultValue: "DEGREE CREDIT PROGRESS")
                                : String(localized: "TOTAL CREDIT PROGRESS", defaultValue: "TOTAL CREDIT PROGRESS")
                        )
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                            .tracking(0.6)
                        Spacer(minLength: 8)
                        Group {
                            if requiredCredits > 0 {
                                HStack(alignment: .firstTextBaseline, spacing: 0) {
                                    Text("\(completedCredits)")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(.primary)
                                    Text(" / \(requiredCredits) Credits")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                }
                            } else {
                                Text("\(completedCredits) cr earned")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.primary)
                            }
                        }
                        .monospacedDigit()
                    }
                    ProgressCapsule(fraction: fraction)
                    if let footnote = programsBreakdown.optionalProgramsFootnote {
                        Text(footnote)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.tertiary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(DesignSystem.Colors.glassCardBase)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(DesignSystem.Colors.chromeStroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .contentShape(Rectangle())
        .accessibilityLabel("Graduation Timeline. \(completedCredits) of \(requiredCredits) credits.")
        .accessibilityHint("Opens the graduation timeline configuration sheet")
    }
}

/// Thin filled capsule used in the compact graduation card. The background sits
/// inside the foreground so we get a single, consistent rounded shape.
private struct ProgressCapsule: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor.opacity(0.65), Color.accentColor],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(0, geo.size.width * CGFloat(min(1.0, max(0.0, fraction)))))
            }
        }
        .frame(height: 6)
    }
}

// MARK: - GPA + Credits Earned mini cards

private struct MiniStatGridRow: View {
    let gpaText: String
    let creditsEarned: Int
    let creditsRequired: Int
    let programsBreakdown: CollegePersistence.DeclaredProgramsCreditsBreakdown

    private var creditsSubtitle: String {
        if creditsRequired > 0 {
            var line = "of \(creditsRequired) required for degree"
            if let footnote = programsBreakdown.optionalProgramsFootnote {
                line += "\n\(footnote)"
            }
            return line
        }
        return "credits earned"
    }

    var body: some View {
        HStack(spacing: 10) {
            cell(label: "CUMULATIVE GPA",
                 value: gpaText,
                 subtitle: "out of 4.00")
            cell(label: "CREDITS EARNED",
                 value: "\(creditsEarned)",
                 subtitle: creditsSubtitle,
                 subtitleLineLimit: programsBreakdown.hasAdditionalPrograms ? 3 : 1)
        }
    }

    @ViewBuilder
    private func cell(label: String, value: String, subtitle: String, subtitleLineLimit: Int = 1) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
                .tracking(0.6)
            Text(value)
                .font(.system(size: 22, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(.primary)
            Text(subtitle)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(subtitleLineLimit)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(DesignSystem.Colors.glassCardBase)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(DesignSystem.Colors.chromeStroke, lineWidth: 1)
        )
    }
}

// MARK: - Stacked progress bar + legend block

/// Renders the 4-segment Completed/InProgress/Planned/Remaining bar and a
/// 4-row legend below it. Uses the same arithmetic as the legacy
/// `CumulativeStatsBar` from `AcademicsView.swift` but in the new palette.
private struct StackedProgressLegendBlock: View {
    let profile: Profile
    let sapStats: (attempted: Int, completed: Int, rate: Double)
    let graduationCreditsRequired: Int
    let programsBreakdown: CollegePersistence.DeclaredProgramsCreditsBreakdown

    @Query(
        sort: [
            SortDescriptor(\PlannerSemester.year, order: .reverse),
            SortDescriptor(\PlannerSemester.seasonOrder, order: .reverse),
        ]
    )
    private var plannerSemesters: [PlannerSemester]

    @EnvironmentObject private var collegePersistence: CollegePersistence
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var creditBuckets: AcademicsPlannerCreditBuckets {
        AcademicsPlannerCreditsBridge.buckets(plannerSemesters: plannerSemesters)
    }

    private var completedCr: Int { creditBuckets.completed }
    private var inProgressCr: Int { creditBuckets.inProgress }
    private var plannedCr: Int { creditBuckets.planned }

    private var required: Int {
        if graduationCreditsRequired > 0 { return graduationCreditsRequired }
        let stored = collegePersistence.primaryCreditsRequired()
        return stored > 0 ? stored : 0
    }

    private var remainingCr: Int { max(0, required - completedCr - inProgressCr - plannedCr) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            stackedBar
            legend
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(DesignSystem.Colors.glassCardBase)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(DesignSystem.Colors.chromeStroke, lineWidth: 1)
        )
        .onAppear {
            
            if reduceMotion {
                appeared = true
            } else {
                withAnimation(.spring(response: 0.72, dampingFraction: 0.86).delay(0.15)) {
                    appeared = true
                }
            }
        }
    }

    private var stackedBar: some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                let total = max(Double(required), 1.0)
                let scale = appeared ? 1.0 : 0.0
                let cFrac = min(Double(completedCr) / total, 1.0) * scale
                let iFrac = min(Double(inProgressCr) / total, 1.0 - cFrac) * scale
                let pFrac = min(Double(plannedCr) / total, 1.0 - cFrac - iFrac) * scale
                let rFrac = max(0.0, 1.0 - cFrac - iFrac - pFrac)
                if cFrac > 0 {
                    Rectangle()
                        .fill(AcademicsStatusPalette.completedDot)
                        .frame(width: geo.size.width * cFrac)
                }
                if iFrac > 0 {
                    Rectangle()
                        .fill(AcademicsStatusPalette.inProgressDot)
                        .frame(width: geo.size.width * iFrac)
                }
                if pFrac > 0 {
                    Rectangle()
                        .fill(AcademicsStatusPalette.plannedDot)
                        .frame(width: geo.size.width * pFrac)
                }
                if rFrac > 0 {
                    Rectangle()
                        .fill(AcademicsStatusPalette.remainingDot)
                        .frame(width: geo.size.width * rFrac)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .animation(.spring(response: 0.72, dampingFraction: 0.86).delay(0.15), value: appeared)
        }
        .frame(height: 8)
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Degree plan")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.tertiary)
                .tracking(0.4)
            HStack {
                legendCell(state: .completed, value: completedCr)
                Spacer(minLength: 4)
                legendCell(state: .inProgress, value: inProgressCr)
            }
            HStack {
                legendCell(state: .planned, value: plannedCr)
                Spacer(minLength: 4)
                legendCell(state: .remaining, value: remainingCr)
            }

            if programsBreakdown.hasAdditionalPrograms {
                Divider().padding(.vertical, 4)
                Text("Additional programs")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .tracking(0.4)
                ForEach(programsBreakdown.additionalPrograms) { program in
                    programLegendRow(program)
                }
            }
        }
    }

    @ViewBuilder
    private func programLegendRow(_ program: CollegePersistence.DeclaredProgramsCreditsBreakdown.AdditionalProgram) -> some View {
        let done = program.progress.completedRoundedInt
        let req = program.progress.requiredRoundedInt
        let left = max(0, req - done)
        let kind = program.kind == .major ? "Major" : "Minor"
        HStack(spacing: 6) {
            Text(kind)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.tertiary)
                .frame(width: 36, alignment: .leading)
            Text(program.displayName)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            Text("\(done)/\(req) · \(left) left")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
    }

    @ViewBuilder
    private func legendCell(state: AcademicsStatusPalette.State, value: Int) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(AcademicsStatusPalette.dot(for: state))
                .frame(width: 7, height: 7)
            Text("\(AcademicsStatusPalette.label(for: state)) \(value) cr")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Vertical compact semester list

private struct SemesterListCompact: View {
    @Query(
        sort: [
            SortDescriptor(\PlannerSemester.year, order: .reverse),
            SortDescriptor(\PlannerSemester.seasonOrder, order: .reverse),
        ]
    )
    private var plannerSemesters: [PlannerSemester]

    @EnvironmentObject private var collegePersistence: CollegePersistence
    @State private var semesterPendingDeleteID: UUID?

    private var summaries: [AcademicsPlannerSemesterSummary] {
        AcademicsPlannerSemesterBridge.summaries(semesters: plannerSemesters)
    }

    private var headerLabel: String {
        let count = summaries.count
        if count == 0 { return "NO SEMESTERS" }
        return "\(count) SEMESTER\(count == 1 ? "" : "S")"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(headerLabel)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
                .tracking(0.6)
                .padding(.horizontal, 4)
                .padding(.top, 6)
                .padding(.bottom, 2)

            VStack(spacing: 6) {
                ForEach(summaries) { summary in
                    SemesterRowCompact(
                        summary: summary,
                        onRequestDelete: { semesterPendingDeleteID = summary.id }
                    )
                }
            }
        }
        .onAppear {
            
        }
        .confirmationDialog(
            "Delete this semester?",
            isPresented: Binding(
                get: { semesterPendingDeleteID != nil },
                set: { if !$0 { semesterPendingDeleteID = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Semester", role: .destructive) {
                if let id = semesterPendingDeleteID {
                    collegePersistence.deleteSemester(id: id)
                }
                semesterPendingDeleteID = nil
            }
            Button("Cancel", role: .cancel) {
                semesterPendingDeleteID = nil
            }
        } message: {
            if let id = semesterPendingDeleteID,
               let summary = summaries.first(where: { $0.id == id }) {
                if summary.courseCount > 0 {
                    Text("“\(summary.displayTitle)” and its \(summary.courseCount) course\(summary.courseCount == 1 ? "" : "s") will be removed from your plan.")
                } else {
                    Text("“\(summary.displayTitle)” will be removed from your plan.")
                }
            }
        }
    }
}

private enum PlannerSemesterSeason: String, CaseIterable, Identifiable {
    case fall = "Fall"
    case winter = "Winter"
    case spring = "Spring"
    case summer = "Summer"

    var id: String { rawValue }

    static func fromStored(_ raw: String) -> PlannerSemesterSeason {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return PlannerSemesterSeason.allCases.first { $0.rawValue.lowercased() == key } ?? .fall
    }
}

private struct SemesterRowCompact: View {
    let summary: AcademicsPlannerSemesterSummary
    let onRequestDelete: () -> Void
    @EnvironmentObject private var collegePersistence: CollegePersistence
    @State private var isHovered = false
    @State private var isEditing = false
    @State private var draftSeason: PlannerSemesterSeason = .fall
    @State private var draftYear: Int = Calendar.current.component(.year, from: Date())
    @FocusState private var yearFieldFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(AcademicsStatusPalette.dot(for: summary.dominantState))
                .frame(width: 8, height: 8)

            if isEditing {
                editingControls
            } else {
                Button {
                    beginEditing()
                } label: {
                    Text(summary.displayTitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .help("Edit semester")
            }

            Spacer(minLength: 4)

            if !isEditing {
                Text("\(summary.totalCredits) cr")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                StatusPill(state: summary.dominantState)
            }

            if isEditing {
                Button(action: commitEditing) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .help("Save")
                .keyboardShortcut(.defaultAction)

                Button(action: cancelEditing) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Cancel")
                .keyboardShortcut(.cancelAction)
            } else if isHovered {
                Button(action: beginEditing) {
                    Image(systemName: "pencil")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Edit semester")

                Button(action: onRequestDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.red.opacity(0.85))
                }
                .buttonStyle(.plain)
                .help("Delete semester")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, isEditing ? 10 : 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(DesignSystem.Colors.glassCardBase)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(
                    isEditing ? Color.accentColor.opacity(0.45) : DesignSystem.Colors.chromeStroke,
                    lineWidth: 1
                )
        )
        .onHover { isHovered = $0 }
        .contextMenu {
            Button("Edit Semester") { beginEditing() }
            Button("Delete Semester", role: .destructive, action: onRequestDelete)
        }
        .onTapGesture(count: 2) {
            if !isEditing { beginEditing() }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(summary.displayTitle), \(summary.totalCredits) credits, \(AcademicsStatusPalette.label(for: summary.dominantState))")
    }

    private var editingControls: some View {
        HStack(spacing: 6) {
            Menu {
                ForEach(PlannerSemesterSeason.allCases) { season in
                    Button(season.rawValue) { draftSeason = season }
                }
            } label: {
                Text(draftSeason.rawValue)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.secondary.opacity(0.12))
                    )
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            HStack(spacing: 4) {
                Button {
                    draftYear = max(2000, draftYear - 1)
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 9, weight: .bold))
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)

                TextField("", value: $draftYear, format: .number)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .multilineTextAlignment(.center)
                    .frame(width: 44)
                    .focused($yearFieldFocused)
                    .onSubmit { commitEditing() }

                Button {
                    draftYear = min(2099, draftYear + 1)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 9, weight: .bold))
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.secondary.opacity(0.08))
            )
        }
    }

    private func beginEditing() {
        draftSeason = PlannerSemesterSeason.fromStored(summary.season)
        draftYear = summary.year
        isEditing = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            yearFieldFocused = true
        }
    }

    private func commitEditing() {
        collegePersistence.updateSemesterDetails(
            id: summary.id,
            season: draftSeason.rawValue,
            year: draftYear
        )
        isEditing = false
        yearFieldFocused = false
    }

    private func cancelEditing() {
        isEditing = false
        yearFieldFocused = false
    }
}

private struct StatusPill: View {
    let state: AcademicsStatusPalette.State

    var body: some View {
        Text(AcademicsStatusPalette.label(for: state))
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(AcademicsStatusPalette.pillForeground(for: state))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(AcademicsStatusPalette.pillBackground(for: state))
            )
    }
}

// MARK: - Add Semester button

private struct AddSemesterButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "calendar.badge.plus")
                    .font(.system(size: 13, weight: .semibold))
                Text("Add Semester")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(DesignSystem.Colors.glassCardBase)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        style: StrokeStyle(lineWidth: 1, dash: [4])
                    )
                    .foregroundStyle(Color.primary.opacity(0.18))
            )
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .accessibilityLabel("Add Semester")
    }
}
