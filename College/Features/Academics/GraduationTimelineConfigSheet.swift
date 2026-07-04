// GraduationTimelineConfigSheet.swift
// Feature: Academics
// Purpose: Academics module — GraduationTimelineConfigSheet.
// Data: CollegePersistence / repositories when applicable.

// GraduationTimelineConfigSheet.swift
// The configuration sheet hosted from the compact Graduation Timeline card.
// Provides:
//   • A pacing header (credits-left + completed/in-progress/planned split).
//   • A target-term picker (next 8 terms after current).
//   • Per-term steppers with status pill + recommended even-split reset.
//   • Live constraints footer with engine + prereq warnings.
//   • Confirm-on-save dialog. Persists structured target + per-term caps and
//     posts `Notification.Name.graduationPlanChanged` so the rest of the app
//     refreshes immediately.

@preconcurrency import AppKit
import CollegeAcademics
import SwiftUI

struct GraduationTimelineConfigSheet: View {
    @Environment(AppContainer.self) private var container
    private var persistence: CollegePersistence { container.persistence }
    let academicProfile: AcademicProfile?
    let requiredCredits: Int
    let completedCredits: Int
    let inProgressCredits: Int
    let plannedCredits: Int

    @Environment(\.dismiss) private var dismiss
    private var collegePersistence: CollegePersistence { container.persistence }
    /// Per-term cap state, keyed by `"<year>-<season>"`. Initialized from the
    /// stored `GraduationPlanTermEntity` rows (or the recommended even-split
    /// when none exist yet). Saving flushes this map back into local store.
    @State private var caps: [String: Int] = [:]
    @State private var targetYear: Int = 0
    @State private var targetSeason: String = ""
    @State private var showConfirm: Bool = false
    @State private var didLoadInitialState: Bool = false
    /// Index of the target-term pill currently centered by keyboard/scroll-wheel navigation.
    @State private var termScrollAnchor: Int = 0
    /// Drives the staggered entrance reveal of the sheet's cards.
    @State private var hasAnimatedIn: Bool = false

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage("ui.reduceMotion") private var prefReduceMotion = false
    private var motionReduced: Bool { systemReduceMotion || prefReduceMotion }

    /// Shared spring used for in-place content changes (numbers, rows, banners).
    private var contentAnimation: Animation {
        motionReduced ? .easeOut(duration: 0.12) : .spring(response: 0.34, dampingFraction: 0.86)
    }

    // MARK: - Degree readiness

    /// Whether the active profile has at least one declared major/degree.
    private var hasSelectedDegree: Bool {
        guard let academicProfile else { return false }
        return !collegePersistence.resolvedMajorNames(for: academicProfile).isEmpty
    }

    /// A degree with zero required credits means the catalog scraper has not produced
    /// requirement data yet — there is nothing to pace against.
    private var hasDegreeRequirementData: Bool { requiredCredits > 0 }

    // MARK: - Computed properties

    private var currentTerm: (year: Int, season: String) {
        GraduationTimelineEngine.currentTerm()
    }

    private var policyBand: GraduationTimelineEngine.PolicyBand {
        let isGraduate = !DegreeConfiguration.isUndergraduate(
            academicProfile?.degreeLevel ?? collegePersistence.primaryDegreeLevel(default: "")
        )
        return GraduationTimelineEngine.policyBand(
            policyInput: GraduationTimelineEngine.PolicyInput(
                policies: collegePersistence.activeSchoolPolicies()
            ),
            isGraduate: isGraduate
        )
    }

    private var futureTerms: [(year: Int, season: String)] {
        guard targetYear > 0, !targetSeason.isEmpty else { return [] }
        let terms = GraduationTimelineEngine.enumerateTerms(
            from: currentTerm,
            through: (targetYear, targetSeason)
        )
        // Drop the very first entry — it's the current term, which the user
        // can't change a cap for (in-progress work).
        return Array(terms.dropFirst())
    }

    private func capKey(year: Int, season: String) -> String { "\(year)-\(season)" }

    private var futureCapsArray: [Int] {
        futureTerms.map { caps[capKey(year: $0.year, season: $0.season)] ?? policyBand.minFullTime }
    }

    private var summary: GraduationTimelineEngine.Summary {
        GraduationTimelineEngine.summary(
            completed: completedCredits,
            inProgress: inProgressCredits,
            planned: plannedCredits,
            requiredTotal: requiredCredits,
            futureCaps: futureCapsArray
        )
    }

    private var prereqWarnings: [GraduationTimelinePrereqValidator.Warning] {
        let scheduled = collegePersistence.graduationPlanScheduledCourses(for: academicProfile)
        return GraduationTimelinePrereqValidator.validate(
            scheduledCourses: scheduled,
            catalogLookup: { code in
                collegePersistence.getCatalogCourse(code: code)
            }
        )
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.windowBackground)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                titleBar
                Divider()
                if hasDegreeRequirementData {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            pacingHeader
                                .modifier(TimelineEntranceModifier(index: 0, isVisible: hasAnimatedIn, reduceMotion: motionReduced))
                            targetTermPicker
                                .modifier(TimelineEntranceModifier(index: 1, isVisible: hasAnimatedIn, reduceMotion: motionReduced))
                            termList
                                .modifier(TimelineEntranceModifier(index: 2, isVisible: hasAnimatedIn, reduceMotion: motionReduced))
                            constraintsFooter
                                .modifier(TimelineEntranceModifier(index: 3, isVisible: hasAnimatedIn, reduceMotion: motionReduced))
                        }
                        .padding(DesignSystem.Spacing.lg)
                    }
                    .scrollIndicators(.hidden)
                    .transition(.opacity)
                } else {
                    degreeEmptyState
                        .modifier(TimelineEntranceModifier(index: 0, isVisible: hasAnimatedIn, reduceMotion: motionReduced))
                        .transition(.opacity)
                }
            }
        }
        .frame(
            minWidth: 640, idealWidth: 720, maxWidth: 820,
            minHeight: 720, idealHeight: 820, maxHeight: 960
        )
        .dismissOnOutsideClickForSheet()
        .onAppear {
            loadInitialStateIfNeeded()
            guard !hasAnimatedIn else { return }
            // Defer one runloop so the pre-reveal state renders before animating in.
            DispatchQueue.main.async { hasAnimatedIn = true }
        }
        .confirmationDialog(
            "Save Graduation Timeline?",
            isPresented: $showConfirm,
            titleVisibility: .visible
        ) {
            Button("Save") { commitSave() }
            Button("Keep editing", role: .cancel) {}
        } message: {
            Text(confirmMessage)
        }
    }

    // MARK: - Title bar

    private var titleBar: some View {
        HStack {
            Button("Cancel") { dismiss() }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)

            Spacer()
            Text("Graduation Timeline")
                .font(DesignSystem.Fonts.main(size: 14, weight: .semibold))
            Spacer()

            Button("Save") { showConfirm = true }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!hasDegreeRequirementData || !summary.isAchievable || futureTerms.isEmpty)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.thinMaterial)
    }

    // MARK: - Pacing header

    private var pacingHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text("\(summary.remainingNeeded)")
                    .font(DesignSystem.Fonts.main(size: 36, weight: .bold))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(summary.remainingNeeded)))
                    .animation(contentAnimation, value: summary.remainingNeeded)
                Text("credits left to graduate")
                    .font(DesignSystem.Fonts.main(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                if !futureTerms.isEmpty {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("AVG PACE NEEDED")
                            .font(DesignSystem.Fonts.main(size: 9, weight: .bold))
                            .tracking(0.6)
                            .foregroundStyle(.secondary)
                        Text(String(format: "%.1f cr/term", summary.avgPaceNeeded))
                            .font(DesignSystem.Fonts.main(size: 14, weight: .semibold))
                            .monospacedDigit()
                            .contentTransition(.numericText(value: summary.avgPaceNeeded))
                            .animation(contentAnimation, value: summary.avgPaceNeeded)
                    }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(contentAnimation, value: futureTerms.isEmpty)

            HStack(spacing: 14) {
                pacingChip(label: "Completed", value: summary.completed, state: .completed)
                pacingChip(label: "In Progress", value: summary.inProgress, state: .inProgress)
                pacingChip(label: "Planned", value: summary.planned, state: .planned)
            }

            stackedProgress
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
    private func pacingChip(label: String, value: Int, state: AcademicsStatusPalette.State) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(AcademicsStatusPalette.dot(for: state))
                .frame(width: 7, height: 7)
            Text("\(value) cr")
                .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(value)))
                .animation(contentAnimation, value: value)
            Text(label)
                .font(DesignSystem.Fonts.main(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private var stackedProgress: some View {
        GeometryReader { geo in
            let total = max(Double(requiredCredits), 1.0)
            let cFrac = min(Double(summary.completed) / total, 1.0)
            let iFrac = min(Double(summary.inProgress) / total, 1.0 - cFrac)
            let pFrac = min(Double(summary.planned) / total, 1.0 - cFrac - iFrac)
            let rFrac = max(0.0, 1.0 - cFrac - iFrac - pFrac)
            // Always render every segment (width 0 when empty) so the bar grows/shrinks
            // smoothly instead of popping segments in and out.
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
            .animation(motionReduced ? nil : .spring(response: 0.5, dampingFraction: 0.9), value: cFrac)
            .animation(motionReduced ? nil : .spring(response: 0.5, dampingFraction: 0.9), value: iFrac)
            .animation(motionReduced ? nil : .spring(response: 0.5, dampingFraction: 0.9), value: pFrac)
        }
        .frame(height: 10)
    }

    // MARK: - Target term picker

    private var targetTermPicker: some View {
        let candidates = GraduationTimelineEngine.suggestTargetTerms(from: currentTerm)
        return VStack(alignment: .leading, spacing: 10) {
            sectionHeader("TARGET GRADUATION TERM")

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(candidates.enumerated()), id: \.offset) { idx, term in
                            targetPill(year: term.year, season: term.season)
                                .id(idx)
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 8)
                }
                .scrollIndicators(.hidden)
                .focusable()
                .onKeyPress(.leftArrow) {
                    moveTermScroll(-1, count: candidates.count, proxy: proxy)
                    return .handled
                }
                .onKeyPress(.rightArrow) {
                    moveTermScroll(1, count: candidates.count, proxy: proxy)
                    return .handled
                }
                .background(
                    HorizontalWheelScrollRedirector { direction in
                        moveTermScroll(direction, count: candidates.count, proxy: proxy)
                    }
                )
                .onAppear {
                    if let selected = selectedCandidateIndex(in: candidates) {
                        termScrollAnchor = selected
                        proxy.scrollTo(selected, anchor: .center)
                    }
                }
            }

            Text(targetSummaryLine)
                .font(DesignSystem.Fonts.main(size: 11))
                .foregroundStyle(.secondary)
                .id(targetSummaryLine)
                .transition(.opacity)
                .animation(contentAnimation, value: targetSummaryLine)
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
    private func targetPill(year: Int, season: String) -> some View {
        let isSelected = (year == targetYear && season.caseInsensitiveCompare(targetSeason) == .orderedSame)
        Button {
            withAnimation(contentAnimation) {
                targetYear = year
                targetSeason = season
                hydrateCapsForFutureTerms()
            }
        } label: {
            Text(verbatim: "\(season) \(year)")
                .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .foregroundStyle(isSelected ? .white : Color.accentColor)
                .background(
                    Capsule().fill(isSelected ? Color.accentColor : Color.accentColor.opacity(0.10))
                )
                .scaleEffect(isSelected && !motionReduced ? 1.04 : 1.0)
                .shadow(
                    color: Color.accentColor.opacity(isSelected && !motionReduced ? 0.35 : 0),
                    radius: 6, y: 2
                )
                .animation(.spring(response: 0.30, dampingFraction: 0.7), value: isSelected)
        }
        .buttonStyle(TimelinePillButtonStyle(reduceMotion: motionReduced))
        .sensoryFeedback(.selection, trigger: isSelected)
    }

    private var targetSummaryLine: String {
        guard targetYear > 0 else {
            return "Pick a target graduation term to see your pacing plan."
        }
        let active = max(0, futureTerms.count)
        return "Choose graduation: \(targetSeason) \(targetYear) → \(active) active term\(active == 1 ? "" : "s") ahead"
    }

    /// Index of the currently selected target term within the candidate list.
    private func selectedCandidateIndex(in candidates: [(year: Int, season: String)]) -> Int? {
        candidates.firstIndex {
            $0.year == targetYear && $0.season.caseInsensitiveCompare(targetSeason) == .orderedSame
        }
    }

    /// Moves the horizontally-scrolled target-term row by one pill in `direction`
    /// (−1 = left, +1 = right) and animates the new anchor into view. Used by both
    /// arrow keys and the mouse scroll wheel.
    private func moveTermScroll(_ direction: Int, count: Int, proxy: ScrollViewProxy) {
        guard count > 0 else { return }
        let next = max(0, min(termScrollAnchor + direction, count - 1))
        guard next != termScrollAnchor else { return }
        termScrollAnchor = next
        withAnimation(.easeOut(duration: 0.18)) {
            proxy.scrollTo(next, anchor: .center)
        }
    }

    // MARK: - Degree empty state

    private var degreeEmptyState: some View {
        ContentUnavailableView {
            Label(
                hasSelectedDegree ? "No degree requirements found" : "No degree selected",
                systemImage: hasSelectedDegree ? "doc.text.magnifyingglass" : "graduationcap"
            )
        } description: {
            Text(degreeEmptyStateMessage)
        } actions: {
            Button(degreeEmptyStateActionTitle) { handleDegreeEmptyStateAction() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(DesignSystem.Spacing.xl)
    }

    private var degreeEmptyStateMessage: String {
        if hasSelectedDegree {
            return "We couldn't find any credit requirements for your degree. Run the catalog scraper to import your program's required courses and credits, then come back to plan your graduation timeline."
        }
        return "Add your major in your profile so we can build a graduation plan. Every degree needs declared programs to calculate the credits required to graduate."
    }

    private var degreeEmptyStateActionTitle: String {
        hasSelectedDegree ? "Open Catalog Settings" : "Select a Degree"
    }

    private func handleDegreeEmptyStateAction() {
        let routeToSettings = hasSelectedDegree
        dismiss()
        Task { @MainActor in
            if routeToSettings {
                _ = AskCollegeCoordinator.openSettingsSection(.academics)
            } else {
                _ = AskCollegeCoordinator.navigateToPage(.profile)
            }
        }
    }

    // MARK: - Per-term list

    private var termList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionHeader("TERM-BY-TERM CREDIT LOAD")
                Spacer()
                Button("Reset to Recommended", action: resetToRecommended)
                    .buttonStyle(.plain)
                    .font(DesignSystem.Fonts.main(size: 11, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .disabled(futureTerms.isEmpty)
            }

            Group {
                if futureTerms.isEmpty {
                    Text("Select a target term above to plan term-by-term credit loads.")
                        .font(DesignSystem.Fonts.main(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 16)
                        .transition(.opacity)
                } else {
                    VStack(spacing: 6) {
                        ForEach(Array(futureTerms.enumerated()), id: \.offset) { _, term in
                            termRow(year: term.year, season: term.season)
                                .transition(.asymmetric(
                                    insertion: .opacity.combined(with: .move(edge: .top)),
                                    removal: .opacity.combined(with: .scale(scale: 0.96))
                                ))
                        }
                    }
                }
            }
            .animation(contentAnimation, value: targetYear)
            .animation(contentAnimation, value: targetSeason)
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
    private func termRow(year: Int, season: String) -> some View {
        let key = capKey(year: year, season: season)
        let cap = caps[key] ?? policyBand.minFullTime
        let status = GraduationTimelineEngine.status(
            forCap: cap,
            isHistorical: false,
            isCurrent: false,
            band: policyBand
        )
        let stateColor = palette(for: status.state)

        HStack(spacing: 12) {
            Text(verbatim: "\(season) \(year)")
                .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 100, alignment: .leading)

            statusPill(state: status.state)

            Spacer(minLength: 4)

            Stepper(
                value: Binding(
                    get: { caps[key] ?? policyBand.minFullTime },
                    set: { newValue in
                        withAnimation(contentAnimation) {
                            caps[key] = max(0, min(newValue, 24))
                        }
                    }
                ),
                in: 0...24
            ) {
                Text("\(cap) cr")
                    .font(DesignSystem.Fonts.main(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .frame(minWidth: 56, alignment: .trailing)
            }
            .labelsHidden()
            Text("\(cap) cr")
                .font(DesignSystem.Fonts.main(size: 13, weight: .semibold))
                .monospacedDigit()
                .frame(minWidth: 56, alignment: .trailing)
                .contentTransition(.numericText(value: Double(cap)))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(stateColor.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(stateColor.opacity(0.35), lineWidth: 1)
        )
        .animation(contentAnimation, value: cap)
    }

    private func palette(for state: GraduationTimelineEngine.CreditState) -> Color {
        switch state {
        case .sufficient:       return AcademicsStatusPalette.completedDot
        case .underAllocated:   return AcademicsStatusPalette.inProgressDot
        case .belowFullTime:    return AcademicsStatusPalette.remainingDot
        case .overloaded:       return AcademicsStatusPalette.inProgressDot
        case .criticalOverload: return Color.red
        }
    }

    @ViewBuilder
    private func statusPill(state: GraduationTimelineEngine.CreditState) -> some View {
        let (label, palette): (String, AcademicsStatusPalette.State) = {
            switch state {
            case .sufficient:       return ("On track", .completed)
            case .underAllocated:   return ("Under", .inProgress)
            case .belowFullTime:    return ("Empty", .remaining)
            case .overloaded:       return ("Heavy", .inProgress)
            case .criticalOverload: return ("Risky", .inProgress)
            }
        }()
        Text(label)
            .font(DesignSystem.Fonts.main(size: 10, weight: .semibold))
            .foregroundStyle(AcademicsStatusPalette.pillForeground(for: palette))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(AcademicsStatusPalette.pillBackground(for: palette))
            )
    }

    // MARK: - Constraints footer

    private var constraintsFooter: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("CONSTRAINTS & WARNINGS")

            let totalAllocated = summary.allocatedAcrossFutureTerms
            let balanced = totalAllocated >= summary.remainingNeeded
            let banner = balanced
                ? "Allocated \(totalAllocated) cr of \(summary.remainingNeeded) required."
                : "Allocation short by \(summary.deficitToTarget) cr — add credits to a future term or extend graduation."
            HStack(spacing: 8) {
                Image(systemName: balanced ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(balanced ? AcademicsStatusPalette.completedDot : Color.red)
                    .contentTransition(.symbolEffect(.replace))
                Text(banner)
                    .font(DesignSystem.Fonts.main(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                    .id(banner)
                    .transition(.opacity)
                Spacer()
            }

            // Cap-level warnings.
            ForEach(Array(termWarnings.enumerated()), id: \.offset) { _, message in
                warningRow(symbol: "exclamationmark.bubble.fill", text: message)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Prerequisite warnings.
            ForEach(prereqWarnings) { w in
                warningRow(symbol: "link.circle.fill", text: w.message)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if termWarnings.isEmpty && prereqWarnings.isEmpty && balanced {
                Text("No constraint issues detected.")
                    .font(DesignSystem.Fonts.main(size: 11))
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
        }
        .animation(contentAnimation, value: summary.allocatedAcrossFutureTerms)
        .animation(contentAnimation, value: summary.remainingNeeded)
        .animation(contentAnimation, value: termWarnings)
        .animation(contentAnimation, value: prereqWarnings.map(\.id))
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

    private var termWarnings: [String] {
        var out: [String] = []
        for term in futureTerms {
            let key = capKey(year: term.year, season: term.season)
            let cap = caps[key] ?? policyBand.minFullTime
            let status = GraduationTimelineEngine.status(
                forCap: cap,
                isHistorical: false,
                isCurrent: false,
                band: policyBand
            )
            for w in status.warnings {
                out.append("\(term.season) \(term.year): \(w)")
            }
        }
        return out
    }

    @ViewBuilder
    private func warningRow(symbol: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol)
                .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                .foregroundStyle(Color.orange)
            Text(text)
                .font(DesignSystem.Fonts.main(size: 11))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
    }

    // MARK: - Section header

    @ViewBuilder
    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
            .foregroundStyle(.secondary)
            .tracking(0.8)
    }

    // MARK: - State hydration

    private func loadInitialStateIfNeeded() {
        guard !didLoadInitialState else { return }
        didLoadInitialState = true

        if let profile = academicProfile,
           let target = collegePersistence.structuredExpectedGraduation(for: profile) {
            targetYear = target.year
            targetSeason = target.season
        } else {
            // Default to two academic years out.
            let suggestions = GraduationTimelineEngine.suggestTargetTerms(from: currentTerm, count: 8)
            let pick = suggestions.dropFirst(4).first ?? suggestions.last
            if let pick {
                targetYear = pick.year
                targetSeason = pick.season
            }
        }

        // Pull existing caps from local store.
        if let profile = academicProfile {
            let terms = collegePersistence.graduationPlanTerms(for: profile)
            for t in terms {
                let key = capKey(year: Int(t.year), season: t.season)
                caps[key] = Int(t.plannedCreditCap)
            }
        }
        hydrateCapsForFutureTerms()
    }

    /// After the target term changes, fill in default caps for any new terms
    /// the user hasn't customized yet. Doesn't clobber existing entries so the
    /// user's manual tweaks survive a target shuffle.
    private func hydrateCapsForFutureTerms() {
        guard !futureTerms.isEmpty else { return }
        let missing = futureTerms.filter { caps[capKey(year: $0.year, season: $0.season)] == nil }
        guard !missing.isEmpty else { return }
        let recommended = GraduationTimelineEngine.recommendedEvenSplit(
            remainingCredits: summary.remainingNeeded,
            futureTermCount: futureTerms.count,
            band: policyBand
        )
        for (idx, term) in futureTerms.enumerated() {
            let key = capKey(year: term.year, season: term.season)
            if caps[key] == nil, idx < recommended.count {
                caps[key] = recommended[idx]
            }
        }
    }

    // MARK: - Reset / save

    private func resetToRecommended() {
        let recommended = GraduationTimelineEngine.recommendedEvenSplit(
            remainingCredits: GraduationTimelineEngine.remainingCreditsToGraduate(
                completed: completedCredits,
                inProgress: inProgressCredits,
                planned: plannedCredits,
                requiredTotal: requiredCredits
            ),
            futureTermCount: futureTerms.count,
            band: policyBand
        )
        withAnimation(contentAnimation) {
            for (idx, term) in futureTerms.enumerated() where idx < recommended.count {
                caps[capKey(year: term.year, season: term.season)] = recommended[idx]
            }
        }
    }

    private var confirmMessage: String {
        let avg = String(format: "%.1f", summary.avgPaceNeeded)
        let count = futureTerms.count
        let target = targetYear > 0 ? "\(targetSeason) \(targetYear)" : "your selected term"
        return "You are saving a custom \(count)-term timeline averaging \(avg) cr/term to graduate in \(target)."
    }

    private func commitSave() {
        guard let profile = academicProfile else {
            dismiss()
            return
        }

        collegePersistence.setStructuredExpectedGraduation(
            year: targetYear,
            season: targetSeason,
            on: profile
        )
        // Wipe and rewrite so the persisted set matches the on-screen state
        // exactly — important when the user shrinks the target window and
        // some old terms shouldn't be in the plan anymore.
        collegePersistence.clearGraduationPlanTerms(for: profile)
        for term in futureTerms {
            let key = capKey(year: term.year, season: term.season)
            let cap = caps[key] ?? policyBand.minFullTime
            collegePersistence.upsertGraduationPlanTerm(
                profile: profile,
                year: term.year,
                season: term.season,
                plannedCreditCap: cap,
                note: nil
            )
        }
        NotificationCenter.default.post(name: .graduationPlanChanged, object: nil)
        dismiss()
    }
}

/// Staggered fade/slide/blur reveal for the sheet's cards. Honors Reduce Motion by
/// dropping the offset/blur and shortening the timing.
private struct TimelineEntranceModifier: ViewModifier {
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

/// Button style for the target-term pills: a springy press scale (suppressed under
/// Reduce Motion) so taps feel responsive.
private struct TimelinePillButtonStyle: ButtonStyle {
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.92 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// Translates plain mouse scroll-wheel events that occur over a horizontal scroll
/// region into discrete left/right steps, so mouse users (not just trackpad users)
/// can move through the target-term row. Trackpad gestures keep their native
/// horizontal scrolling because precise-delta events are passed straight through.
private struct HorizontalWheelScrollRedirector: NSViewRepresentable {
    /// Called with −1 (scroll left) or +1 (scroll right) per wheel notch.
    let onStep: (Int) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onStep: onStep) }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onStep = onStep
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator {
        var onStep: (Int) -> Void
        private weak var hostView: NSView?
        private var monitor: Any?

        init(onStep: @escaping (Int) -> Void) { self.onStep = onStep }

        func attach(to view: NSView) {
            hostView = view
            let host = SendableViewBox(view)
            let stepHandler = SendableStepHandler(onStep)
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
                let boxedEvent = SendableEventBox(event)
                let consumed = MainActor.assumeIsolated {
                    HorizontalWheelScrollRedirector.shouldConsumeScrollWheel(
                        event: boxedEvent.event,
                        host: host.view,
                        onStep: stepHandler.call
                    )
                }
                return consumed ? nil : event
            }
        }

        func detach() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            monitor = nil
        }
    }

    @MainActor
    static func shouldConsumeScrollWheel(
        event: NSEvent,
        host: NSView,
        onStep: (Int) -> Void
    ) -> Bool {
        guard let window = host.window, event.window === window else { return false }
        if event.hasPreciseScrollingDeltas { return false }

        let frameInWindow = host.convert(host.bounds, to: nil)
        guard frameInWindow.contains(event.locationInWindow) else { return false }

        let delta = event.scrollingDeltaY != 0 ? event.scrollingDeltaY : event.scrollingDeltaX
        guard delta != 0 else { return false }
        onStep(delta > 0 ? -1 : 1)
        return true
    }
}

private struct SendableEventBox: @unchecked Sendable {
    let event: NSEvent
    init(_ event: NSEvent) { self.event = event }
}

private struct SendableViewBox: @unchecked Sendable {
    let view: NSView
    init(_ view: NSView) { self.view = view }
}

private struct SendableStepHandler: @unchecked Sendable {
    let call: (Int) -> Void
    init(_ call: @escaping (Int) -> Void) { self.call = call }
}
