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
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        pacingHeader
                        targetTermPicker
                        termList
                        constraintsFooter
                    }
                    .padding(20)
                }
            }
        }
        .frame(
            minWidth: 640, idealWidth: 720, maxWidth: 820,
            minHeight: 720, idealHeight: 820, maxHeight: 960
        )
        .dismissOnOutsideClickForSheet()
        .onAppear { loadInitialStateIfNeeded() }
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
                .font(.system(size: 14, weight: .semibold))
            Spacer()

            Button("Save") { showConfirm = true }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!summary.isAchievable || futureTerms.isEmpty)
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
                    .font(.system(size: 36, weight: .bold))
                    .monospacedDigit()
                Text("credits left to graduate")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                if !futureTerms.isEmpty {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("AVG PACE NEEDED")
                            .font(.system(size: 9, weight: .bold))
                            .tracking(0.6)
                            .foregroundStyle(.secondary)
                        Text(String(format: "%.1f cr/term", summary.avgPaceNeeded))
                            .font(.system(size: 14, weight: .semibold))
                            .monospacedDigit()
                    }
                }
            }

            HStack(spacing: 14) {
                pacingChip(label: "Completed", value: summary.completed, state: .completed)
                pacingChip(label: "In Progress", value: summary.inProgress, state: .inProgress)
                pacingChip(label: "Planned", value: summary.planned, state: .planned)
            }

            stackedProgress
        }
        .padding(16)
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
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private var stackedProgress: some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                let total = max(Double(requiredCredits), 1.0)
                let cFrac = min(Double(summary.completed) / total, 1.0)
                let iFrac = min(Double(summary.inProgress) / total, 1.0 - cFrac)
                let pFrac = min(Double(summary.planned) / total, 1.0 - cFrac - iFrac)
                let rFrac = max(0.0, 1.0 - cFrac - iFrac - pFrac)
                if cFrac > 0 {
                    Rectangle().fill(AcademicsStatusPalette.completedDot)
                        .frame(width: geo.size.width * CGFloat(cFrac))
                }
                if iFrac > 0 {
                    Rectangle().fill(AcademicsStatusPalette.inProgressDot)
                        .frame(width: geo.size.width * CGFloat(iFrac))
                }
                if pFrac > 0 {
                    Rectangle().fill(AcademicsStatusPalette.plannedDot)
                        .frame(width: geo.size.width * CGFloat(pFrac))
                }
                if rFrac > 0 {
                    Rectangle().fill(AcademicsStatusPalette.remainingDot)
                        .frame(width: geo.size.width * CGFloat(rFrac))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .frame(height: 10)
    }

    // MARK: - Target term picker

    private var targetTermPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("TARGET GRADUATION TERM")

            let candidates = GraduationTimelineEngine.suggestTargetTerms(from: currentTerm)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(candidates.enumerated()), id: \.offset) { _, term in
                        targetPill(year: term.year, season: term.season)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 2)
            }

            Text(targetSummaryLine)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(16)
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
            targetYear = year
            targetSeason = season
            hydrateCapsForFutureTerms()
        } label: {
            Text("\(season) \(year)")
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .foregroundStyle(isSelected ? .white : Color.accentColor)
                .background(
                    Capsule().fill(isSelected ? Color.accentColor : Color.accentColor.opacity(0.10))
                )
        }
        .buttonStyle(.plain)
    }

    private var targetSummaryLine: String {
        guard targetYear > 0 else {
            return "Pick a target graduation term to see your pacing plan."
        }
        let active = max(0, futureTerms.count)
        return "Choose graduation: \(targetSeason) \(targetYear) → \(active) active term\(active == 1 ? "" : "s") ahead"
    }

    // MARK: - Per-term list

    private var termList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionHeader("TERM-BY-TERM CREDIT LOAD")
                Spacer()
                Button("Reset to Recommended", action: resetToRecommended)
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .disabled(futureTerms.isEmpty)
            }

            if futureTerms.isEmpty {
                Text("Select a target term above to plan term-by-term credit loads.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 16)
            } else {
                VStack(spacing: 6) {
                    ForEach(Array(futureTerms.enumerated()), id: \.offset) { _, term in
                        termRow(year: term.year, season: term.season)
                    }
                }
            }
        }
        .padding(16)
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
            Text("\(season) \(year)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 100, alignment: .leading)

            statusPill(state: status.state)

            Spacer(minLength: 4)

            Stepper(
                value: Binding(
                    get: { caps[key] ?? policyBand.minFullTime },
                    set: { caps[key] = max(0, min($0, 24)) }
                ),
                in: 0...24
            ) {
                Text("\(cap) cr")
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .frame(minWidth: 56, alignment: .trailing)
            }
            .labelsHidden()
            Text("\(cap) cr")
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
                .frame(minWidth: 56, alignment: .trailing)
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
            .font(.system(size: 10, weight: .semibold))
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
                Text(banner)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                Spacer()
            }

            // Cap-level warnings.
            ForEach(Array(termWarnings.enumerated()), id: \.offset) { _, message in
                warningRow(symbol: "exclamationmark.bubble.fill", text: message)
            }

            // Prerequisite warnings.
            ForEach(prereqWarnings) { w in
                warningRow(symbol: "link.circle.fill", text: w.message)
            }

            if termWarnings.isEmpty && prereqWarnings.isEmpty && balanced {
                Text("No constraint issues detected.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
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
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.orange)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
    }

    // MARK: - Section header

    @ViewBuilder
    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
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
        for (idx, term) in futureTerms.enumerated() where idx < recommended.count {
            caps[capKey(year: term.year, season: term.season)] = recommended[idx]
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
