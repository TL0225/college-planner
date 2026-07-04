// ResumeLibraryTableView.swift
// Feature: Career / Resumes
// Purpose: Resume library table aligned with Career list table styling.

import SwiftUI

struct ResumeLibraryTableView: View {
    let resumes: [VaultDocument]
    let collegePersistence: CollegePersistence
    let onOpenProfile: (VaultDocument) -> Void
    let onAddResume: () -> Void
    let onBuildResume: () -> Void
    let onReingest: (VaultDocument) -> Void
    let onSetPrimary: (VaultDocument) -> Void
    let onToggleArchived: (VaultDocument) -> Void
    let onDelete: (VaultDocument) -> Void
    let onQuickLook: (VaultDocument) -> Void

    var body: some View {
        Group {
            if resumes.isEmpty {
                emptyState
            } else {
                listCard
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Card

    private var listCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            actionBar
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

            Divider()
                .opacity(0.35)

            columnHeader
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)

            Divider()
                .opacity(0.35)

            resumeTable
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(DesignSystem.Colors.surface)
                .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .padding(.horizontal, DesignSystem.Spacing.xl)
        .padding(.top, DesignSystem.Spacing.lg)
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            Text("\(resumes.count) resume\(resumes.count == 1 ? "" : "s")")
                .font(DesignSystem.Fonts.main(size: 13, weight: .medium))
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            Button(action: onBuildResume) {
                Text("Build resume")
                    .font(DesignSystem.Fonts.main(size: 13, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("resume.library.buildResume")
            .background(DesignSystem.Colors.surface, in: Capsule(style: .continuous))
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(DesignSystem.Colors.primary.opacity(0.35), lineWidth: 1)
            )

            Button(action: onAddResume) {
                Label("Upload", systemImage: "square.and.arrow.up")
                    .font(DesignSystem.Fonts.main(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .background(DesignSystem.Colors.primary, in: Capsule(style: .continuous))
        }
    }

    private var columnHeader: some View {
        HStack(alignment: .center, spacing: 16) {
            headerLabel("RESUME", width: CareerListTableTheme.columnResume, alignment: .leading)
            headerLabel("TARGET ROLE", width: CareerListTableTheme.columnTargetRole, alignment: .leading)
            headerLabel("UPDATED", width: CareerListTableTheme.columnResumeDate, alignment: .leading)
            headerLabel("ADDED", width: CareerListTableTheme.columnResumeDate, alignment: .leading)
            Color.clear.frame(width: CareerListTableTheme.columnResumeActions)
            Spacer(minLength: 0)
        }
    }

    private func headerLabel(_ title: String, width: CGFloat, alignment: Alignment) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(DesignSystem.Colors.textLight)
            .tracking(0.4)
            .frame(width: width, alignment: alignment)
    }

    private var resumeTable: some View {
        ScrollView(.vertical, showsIndicators: true) {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyVStack(spacing: 8) {
                    ForEach(resumes, id: \.id) { resume in
                        listDataRow(resume)
                    }
                }
                .frame(minWidth: Self.tableContentMinWidth, alignment: .leading)
                .padding(DesignSystem.Spacing.md)
            }
        }
    }

    private static var tableContentMinWidth: CGFloat {
        let columns =
            CareerListTableTheme.columnResume
            + CareerListTableTheme.columnTargetRole
            + CareerListTableTheme.columnResumeDate
            + CareerListTableTheme.columnResumeDate
            + CareerListTableTheme.columnResumeActions
        let gaps: CGFloat = 16 * 5
        let rowPadding: CGFloat = 14 * 2
        return columns + gaps + rowPadding
    }

    private func listDataRow(_ resume: VaultDocument) -> some View {
        let meta = collegePersistence.careerResumeMetadata(for: resume)

        return Button {
            onOpenProfile(resume)
        } label: {
            HStack(alignment: .center, spacing: 16) {
                resumeCell(resume: resume, meta: meta)
                    .frame(width: CareerListTableTheme.columnResume, alignment: .leading)

                Text(targetRole(for: meta))
                    .font(DesignSystem.Fonts.main(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .frame(width: CareerListTableTheme.columnTargetRole, alignment: .leading)

                Text(relativeDate(resume.lastOpenedAt ?? resume.addedAt))
                    .font(DesignSystem.Fonts.main(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(width: CareerListTableTheme.columnResumeDate, alignment: .leading)

                Text(relativeDate(resume.addedAt))
                    .font(DesignSystem.Fonts.main(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(width: CareerListTableTheme.columnResumeDate, alignment: .leading)

                rowActionsMenu(resume: resume, meta: meta)
                    .frame(width: CareerListTableTheme.columnResumeActions)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(minHeight: 56)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.025))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.75)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func resumeCell(resume: VaultDocument, meta: CareerResumeMetadataV1) -> some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(CareerResumeLibraryTheme.accent(for: meta.kind).opacity(0.14))
                Text(ResumeProfileScoring.letterGrade(for: meta.parserHealthPercent))
                    .font(DesignSystem.Fonts.main(size: 14, weight: .bold))
                    .foregroundStyle(CareerResumeLibraryTheme.accent(for: meta.kind))
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(displayTitle(for: resume))
                        .font(DesignSystem.Fonts.main(size: 14, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if resume.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                            .help("Primary resume")
                    }
                }

                statusLine(for: resume, meta: meta)
            }
        }
    }

    @ViewBuilder
    private func statusLine(for resume: VaultDocument, meta: CareerResumeMetadataV1) -> some View {
        if meta.ingestCompletedAt == nil {
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text("Parsing…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else if meta.archived {
            Text("Archived")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if let health = meta.parserHealthPercent {
            Text("Parser health \(health)%")
                .font(.caption)
                .foregroundStyle(CareerResumeLibraryTheme.parserHealthTierColor(for: health))
        } else {
            Text("Ready")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func rowActionsMenu(resume: VaultDocument, meta: CareerResumeMetadataV1) -> some View {
        Menu {
            if !resume.isFavorite {
                Button("Set as primary") { onSetPrimary(resume) }
            }
            Button("Re-analyze") { onReingest(resume) }
            Button("Quick Look") { onQuickLook(resume) }
            Divider()
            Button(meta.archived ? "Unarchive" : "Archive") { onToggleArchived(resume) }
            Button("Delete", role: .destructive) { onDelete(resume) }
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
    }

    // MARK: - Empty

    private var emptyState: some View {
        ResumeRequiredEmptyState(onUpload: onAddResume, onBuild: onBuildResume)
    }

    // MARK: - Helpers

    private func displayTitle(for resume: VaultDocument) -> String {
        let raw = resume.customDisplayName ?? resume.fileName
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Resume" : trimmed
    }

    private func targetRole(for meta: CareerResumeMetadataV1) -> String {
        let role = meta.targetRole?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return role.isEmpty ? "—" : role
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

enum ResumeProfileScoring {
    static func letterGrade(for percent: Int?) -> String {
        guard let percent else { return "—" }
        switch percent {
        case 90...100: return "A"
        case 80..<90: return "B"
        case 70..<80: return "C"
        case 60..<70: return "D"
        default: return "F"
        }
    }

    static func ratingLabel(for percent: Int?) -> String {
        guard let percent else { return "Pending" }
        switch percent {
        case 90...100: return "Excellent"
        case 75..<90: return "Good"
        case 60..<75: return "Fair"
        default: return "Needs work"
        }
    }

    static func ratingColor(for percent: Int?) -> Color {
        CareerResumeLibraryTheme.parserHealthTierColor(for: percent)
    }
}
