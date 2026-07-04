// AcademicsBottomSummaryStrip.swift
// Feature: Academics
// Purpose: Academics module — ProgramCreditStatusStripRow.
// Data: CollegePersistence / repositories when applicable.

// AcademicsBottomSummaryStrip.swift
// Pinned strip at the bottom of the redesigned Academics canvas. Pick a declared program
// (or "All programs") to see Completed / In Progress / Remaining for that scope.

import SwiftUI

struct ProgramCreditStatusStripRow: Identifiable, Equatable {
    static let allProgramsID = "all-programs"

    let id: String
    let title: String
    /// "Major" or "Minor"; nil for the combined row.
    let kindLabel: String?
    /// First declared major — shown as a small badge on the picker chip.
    let isGraduationTarget: Bool
    let completed: Int
    let inProgress: Int
    let remaining: Int
}

struct AcademicsBottomSummaryStrip: View {
    let programs: [ProgramCreditStatusStripRow]
    /// Called when the user picks a chip — use to scroll the requirements breakdown to that program.
    var onSelectProgram: ((String) -> Void)? = nil

    @SceneStorage("academics.bottomStrip.selectedProgramID") private var selectedProgramID: String = ProgramCreditStatusStripRow.allProgramsID

    private var selectedRow: ProgramCreditStatusStripRow {
        programs.first(where: { $0.id == selectedProgramID }) ?? programs.first ?? .placeholder
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if programs.count > 1 {
                programPicker
            }
            creditStatusSection(for: selectedRow)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(DesignSystem.Colors.bgMain)
        .overlay(
            Rectangle()
                .fill(DesignSystem.Colors.chromeStroke)
                .frame(height: 0.5),
            alignment: .top
        )
        .onChange(of: programs.map(\.id)) { _, ids in
            if !ids.contains(selectedProgramID) {
                selectedProgramID = ids.first ?? ProgramCreditStatusStripRow.allProgramsID
            }
        }
    }

    private var programPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(programs) { program in
                    programChip(program)
                }
            }
            .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private func programChip(_ program: ProgramCreditStatusStripRow) -> some View {
        let isSelected = program.id == selectedProgramID
        Button {
            selectedProgramID = program.id
            onSelectProgram?(program.id)
        } label: {
            HStack(spacing: 6) {
                if let kind = program.kindLabel {
                    Text(kind.uppercased())
                        .font(DesignSystem.Fonts.main(size: 9, weight: .bold))
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.65))
                }
                Text(program.id == ProgramCreditStatusStripRow.allProgramsID ? "All" : program.title)
                    .font(DesignSystem.Fonts.main(size: 12, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                    .lineLimit(1)
                if program.isGraduationTarget {
                    Text("DEGREE")
                        .font(DesignSystem.Fonts.main(size: 8, weight: .bold))
                        .foregroundStyle(isSelected ? Color.accentColor.opacity(0.9) : Color.secondary.opacity(0.65))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.10))
                        )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : DesignSystem.Colors.glassCardBase)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        isSelected ? Color.accentColor.opacity(0.45) : DesignSystem.Colors.chromeStroke,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(chipAccessibilityLabel(program, isSelected: isSelected))
    }

    private func chipAccessibilityLabel(_ program: ProgramCreditStatusStripRow, isSelected: Bool) -> String {
        var parts = [program.title]
        if let kind = program.kindLabel { parts.append(kind) }
        if program.isGraduationTarget { parts.append("graduation target") }
        if isSelected { parts.append("selected") }
        return parts.joined(separator: ", ")
    }

    @ViewBuilder
    private func creditStatusSection(for row: ProgramCreditStatusStripRow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(row.title)
                    .font(DesignSystem.Fonts.main(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if row.id == ProgramCreditStatusStripRow.allProgramsID {
                    Text("· planner totals")
                        .font(DesignSystem.Fonts.main(size: 10, weight: .medium))
                        .foregroundStyle(Color.secondary.opacity(0.65))
                } else if let kind = row.kindLabel {
                    Text("· \(kind.lowercased()) requirements")
                        .font(DesignSystem.Fonts.main(size: 10, weight: .medium))
                        .foregroundStyle(Color.secondary.opacity(0.65))
                }
            }

            HStack(spacing: 12) {
                statusCell(state: .completed, value: row.completed)
                statusCell(state: .inProgress, value: row.inProgress)
                statusCell(state: .remaining, value: row.remaining)
            }
        }
    }

    @ViewBuilder
    private func statusCell(state: AcademicsStatusPalette.State, value: Int) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(AcademicsStatusPalette.dot(for: state))
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 0) {
                Text("\(value) cr")
                    .font(DesignSystem.Fonts.main(size: 15, weight: .bold))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                Text(AcademicsStatusPalette.label(for: state))
                    .font(DesignSystem.Fonts.main(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(DesignSystem.Colors.glassCardBase)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(DesignSystem.Colors.chromeStroke, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) credits \(AcademicsStatusPalette.label(for: state))")
    }
}

private extension ProgramCreditStatusStripRow {
    static var placeholder: ProgramCreditStatusStripRow {
        ProgramCreditStatusStripRow(
            id: allProgramsID,
            title: "All programs",
            kindLabel: nil,
            isGraduationTarget: false,
            completed: 0,
            inProgress: 0,
            remaining: 0
        )
    }
}

extension CollegePersistence {
    /// Rows for the Academics bottom strip: combined planner totals plus each declared major/minor.
    func programCreditStatusStripRows(
        majors: [String],
        minors: [String],
        combinedCompleted: Int,
        combinedInProgress: Int,
        combinedPlanned: Int,
        combinedRequired: Int,
        academicProfile: AcademicProfile?
    ) -> [ProgramCreditStatusStripRow] {
        let majorList = majors.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let minorList = minors
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.lowercased() != "none" }

        var programRows: [ProgramCreditStatusStripRow] = []

        for (idx, major) in majorList.enumerated() {
            let buckets = majorProgramCreditStatusBuckets(forMajorDisplay: major, academicProfile: academicProfile)
            programRows.append(
                ProgramCreditStatusStripRow(
                    id: "major|\(major)",
                    title: major,
                    kindLabel: "Major",
                    isGraduationTarget: idx == 0,
                    completed: buckets.completed,
                    inProgress: buckets.inProgress,
                    remaining: buckets.remaining
                )
            )
        }

        for minor in minorList {
            let buckets = minorProgramCreditStatusBuckets(forMinorDisplay: minor, academicProfile: academicProfile)
            programRows.append(
                ProgramCreditStatusStripRow(
                    id: "minor|\(minor)",
                    title: minor,
                    kindLabel: "Minor",
                    isGraduationTarget: false,
                    completed: buckets.completed,
                    inProgress: buckets.inProgress,
                    remaining: buckets.remaining
                )
            )
        }

        let combinedRemaining = max(0, combinedRequired - combinedCompleted - combinedInProgress - combinedPlanned)
        let aggregate: (completed: Int, inProgress: Int, remaining: Int) = {
            guard !programRows.isEmpty else {
                return (combinedCompleted, combinedInProgress, combinedRemaining)
            }
            return (
                programRows.reduce(0) { $0 + $1.completed },
                programRows.reduce(0) { $0 + $1.inProgress },
                programRows.reduce(0) { $0 + $1.remaining }
            )
        }()

        let allPrograms = ProgramCreditStatusStripRow(
            id: ProgramCreditStatusStripRow.allProgramsID,
            title: "All programs",
            kindLabel: nil,
            isGraduationTarget: false,
            completed: aggregate.completed,
            inProgress: aggregate.inProgress,
            remaining: aggregate.remaining
        )

        return [allPrograms] + programRows
    }

    private func majorProgramCreditStatusBuckets(
        forMajorDisplay major: String,
        academicProfile: AcademicProfile?
    ) -> ProgramCreditStatusBuckets {
        if let academicProfile {
            return majorProgramCreditStatusBuckets(forMajorDisplay: major, academicProfile: academicProfile)
        }
        return majorProgramCreditStatusBuckets(forMajorDisplay: major)
    }

    private func minorProgramCreditStatusBuckets(
        forMinorDisplay minor: String,
        academicProfile: AcademicProfile?
    ) -> ProgramCreditStatusBuckets {
        if let academicProfile {
            return minorProgramCreditStatusBuckets(forMinorDisplay: minor, academicProfile: academicProfile)
        }
        return minorProgramCreditStatusBuckets(forMinorDisplay: minor)
    }
}
