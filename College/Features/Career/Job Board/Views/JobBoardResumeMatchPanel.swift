// JobBoardResumeMatchPanel.swift
// Feature: Career
// Purpose: HR-grade resume match panel for job board detail pane.

import SwiftUI
import CollegeCareer

struct JobBoardResumeMatchPanel: View {
    let rows: [CareerResumeMatchRow]
    var matchState: JobBoardDetailMatchState = .scored
    let isLoading: Bool
    let usedPartialFallback: Bool
    let platform: JobBoardPlatform
    let jobTitle: String
    let companyName: String
    let jobDescriptionText: String
    var isPostingTracked: Bool = false
    @Binding var gapParagraph: String?
    var onAddToBoard: (UUID) -> Void
    var onDraftGapParagraph: (CareerResumeMatchRow) -> Void
    var onExportATSSafePDF: (UUID) -> Void
    var onTailorResume: (CareerResumeMatchRow) -> Void

    @State private var gapParagraphResumeID: UUID?
    @State private var showPlatformDetail = false
    @State private var showExperienceGapDetail = false
    @State private var expandedSkillKeys: Set<String> = []

    private var scoringProfile: CareerATSScoringProfile {
        CareerATSScoringProfile.profile(for: platform)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Resume match")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if isLoading {
                    ProgressView().controlSize(.small)
                }
            }

            platformBanner

            switch matchState {
            case .scored:
                scoredContent
            default:
                ResumeRequiredBanner(state: matchState, isLoading: isLoading)
            }
        }
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var scoredContent: some View {
        if rows.isEmpty {
            Text("No match scores yet.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            if usedPartialFallback {
                Text("Partial score — AI model unavailable for full analysis.")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }

            if let recommended = rows.first(where: \.isRecommended) ?? rows.first {
                recommendedRow(recommended)
            }

            ForEach(rows.filter { !$0.isRecommended }) { row in
                compactRow(row)
            }
        }
    }

    @ViewBuilder
    private var platformBanner: some View {
        let profileName = rows.first?.platformProfileName ?? scoringProfile.name
        DisclosureGroup(isExpanded: $showPlatformDetail) {
            VStack(alignment: .leading, spacing: 6) {
                Text(scoringProfile.platformExplanation)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(scoringProfile.tailoringAdvice)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(DesignSystem.Colors.accent)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 4)
        } label: {
            HStack(spacing: 6) {
                Text(profileName)
                    .font(.caption2.weight(.bold))
                Text("scoring")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.accentColor.opacity(0.1), in: Capsule())
        }
        .font(.caption)
    }

    private func recommendedRow(_ row: CareerResumeMatchRow) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(row.displayName)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                HStack(spacing: 4) {
                    if let delta = row.scoreDelta, delta != 0 {
                        Text(delta > 0 ? "↑ +\(delta)" : "↓ \(delta)")
                            .font(.caption2.monospacedDigit().weight(.semibold))
                            .foregroundStyle(delta > 0 ? .green : .red)
                    }
                    Text("\(row.overallScore)%")
                        .font(.title3.monospacedDigit().weight(.bold))
                        .foregroundStyle(CareerResumeLibraryTheme.jobMatchTierColor(for: row.overallScore))
                }
            }

            Text("Recommended")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.green)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.green.opacity(0.12), in: Capsule())

            if let mismatch = row.roleMismatchNote {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "arrow.triangle.branch")
                        .foregroundStyle(.red)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(mismatch)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                        if let target = row.resumeTargetRole, !target.isEmpty {
                            Text("Resume target: \(target) · Role fit \(row.roleFitScore)%")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Role track fit: \(row.roleFitScore)%")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(DesignSystem.Spacing.sm)
                .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }

            if let gapNote = row.experienceGapNote {
                experienceGapBanner(gapNote: gapNote, row: row)
            }

            if row.achievementScore < 40 {
                HStack(spacing: 6) {
                    Image(systemName: "chart.bar.doc.horizontal")
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)
                    Text("Low impact signals — add metrics and scope to bullets (\(row.achievementScore)/100)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(DesignSystem.Spacing.sm)
                .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }

            if let note = row.trajectoryNote ?? row.seniorityAlignmentNote {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            scoreBars(row)

            if let taxonomy = row.skillsGapTaxonomy, !taxonomy.isEmpty {
                skillsGapChips(taxonomy)
            } else {
                labeledSkillChips(matching: row.matchingSkills, missing: row.missingKeywords, partial: false)
            }

            if !row.tip.isEmpty {
                Text(row.tip)
                    .font(.caption)
                    .italic()
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let tips = row.portalTips, !tips.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Portal tips")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(tips, id: \.self) { tip in
                        Text("• \(tip)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if let gaps = row.courseSkillGaps, !gaps.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Closing the gap")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(gaps, id: \.skill) { gap in
                        let courseLabel = [gap.courseCode, gap.courseTitle]
                            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                            .filter { !$0.isEmpty }
                            .joined(separator: " · ")
                        Text(courseLabel.isEmpty
                             ? gap.skill
                             : "\(gap.skill) — \(courseLabel)")
                            .font(.caption2)
                            .foregroundStyle(DesignSystem.Colors.accent)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if let gapParagraph, gapParagraphResumeID == row.resumeDocumentID {
                Text(gapParagraph)
                    .font(.caption)
                    .padding(DesignSystem.Spacing.md)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    .textSelection(.enabled)
            }

            matchActionButtons(for: row)
        }
        .padding(DesignSystem.Spacing.md)
        .background(Color.green.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder
    private func matchActionButtons(for row: CareerResumeMatchRow) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                matchActionButtonGroup(for: row)
            }
            VStack(alignment: .leading, spacing: 8) {
                matchActionButtonGroup(for: row)
            }
        }
    }

    @ViewBuilder
    private func matchActionButtonGroup(for row: CareerResumeMatchRow) -> some View {
        Button("Tailor Resume") {
            onTailorResume(row)
        }
        .buttonStyle(.borderedProminent)
        .accessibilityIdentifier("career.jobMatch.tailorResume")

        if !isPostingTracked {
            Button("Add to Board") {
                onAddToBoard(row.resumeDocumentID)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("career.jobMatch.addToBoard")
        }

        Button("Download ATS-safe PDF") {
            onExportATSSafePDF(row.resumeDocumentID)
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("career.jobMatch.exportATS")

        Button("Draft gap paragraph") {
            gapParagraphResumeID = row.resumeDocumentID
            onDraftGapParagraph(row)
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("career.jobMatch.draftGap")
    }

    @ViewBuilder
    private func experienceGapBanner(gapNote: String, row: CareerResumeMatchRow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                Text(gapNote)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.orange)
            }
            if row.candidateYearsMonths != nil {
                Text("Detected: \(row.candidateYearsMonths ?? "")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            DisclosureGroup("How to frame this gap", isExpanded: $showExperienceGapDetail) {
                Text(row.tip.isEmpty
                     ? "Highlight adjacent experience and transferable skills honestly in your bullets."
                     : row.tip)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
            .font(.caption2)
        }
        .padding(DesignSystem.Spacing.sm)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private func compactRow(_ row: CareerResumeMatchRow) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(row.displayName)
                    .font(.caption.weight(.semibold))
                skillChips(matching: row.matchingSkills.prefix(3).map { $0 }, missing: row.missingKeywords.prefix(2).map { $0 }, partial: true)
            }
            Spacer()
            Text("\(row.overallScore)%")
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(CareerResumeLibraryTheme.jobMatchTierColor(for: row.overallScore))
        }
        .padding(.vertical, 4)
    }

    private func scoreBars(_ row: CareerResumeMatchRow) -> some View {
        let profile = scoringProfile
        return VStack(spacing: 4) {
            miniBar(label: profile.keywordBarLabel, value: row.keywordScore)
            miniBar(label: "Semantic", value: row.semanticScore)
            miniBar(label: "Experience", value: row.experienceScore)
            miniBar(label: "Transferable", value: row.transferableScore)
            miniBar(label: "Achievement", value: row.achievementScore)
            miniBar(label: "Overall", value: row.overallScore)
        }
    }

    private func miniBar(label: String, value: Int) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)
            ProgressView(value: Double(value), total: 100)
                .tint(CareerResumeLibraryTheme.jobMatchTierColor(for: value))
            Text("\(value) / 100")
                .font(.caption2.monospacedDigit())
                .frame(width: 52, alignment: .trailing)
        }
    }

    @ViewBuilder
    private func skillsGapChips(_ entries: [SkillGapEntry]) -> some View {
        FlowLayout(spacing: 6) {
            ForEach(entries, id: \.skill) { entry in
                Button {
                    if expandedSkillKeys.contains(entry.skill) {
                        expandedSkillKeys.remove(entry.skill)
                    } else {
                        expandedSkillKeys.insert(entry.skill)
                    }
                } label: {
                    TaxonomySkillChip(entry: entry, expanded: expandedSkillKeys.contains(entry.skill))
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func labeledSkillChips(matching: [String], missing: [String], partial: Bool) -> some View {
        if !matching.isEmpty {
            Text("In your resume")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            skillChips(matching: matching, missing: [], partial: partial)
        }
        if !missing.isEmpty {
            Text("Missing from resume")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.top, matching.isEmpty ? 0 : 4)
            skillChips(matching: [], missing: missing, partial: partial)
        }
    }

    @ViewBuilder
    private func skillChips(matching: [String], missing: [String], partial: Bool) -> some View {
        FlowLayout(spacing: 6) {
            ForEach(matching, id: \.self) { skill in
                JobBoardSkillChip(text: skill, state: .match)
            }
            ForEach(missing, id: \.self) { skill in
                JobBoardSkillChip(text: skill, state: partial ? .partialMiss : .miss)
            }
        }
    }
}

private struct TaxonomySkillChip: View {
    let entry: SkillGapEntry
    let expanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: iconName)
                    .font(.caption2.weight(.bold))
                Text(entry.skill)
                    .font(.caption2)
            }
            if expanded, let evidence = entry.evidenceBullet ?? entry.recencyNote {
                Text(evidence)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .foregroundStyle(foreground)
        .background(background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var iconName: String {
        switch entry.status {
        case "direct": return "checkmark"
        case "transferable": return "arrow.triangle.branch"
        case "stale": return "clock"
        default: return "xmark"
        }
    }

    private var foreground: Color {
        switch entry.status {
        case "direct": return .green
        case "transferable": return .yellow
        case "stale": return .orange
        default: return .red
        }
    }

    private var background: Color {
        foreground.opacity(0.12)
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        layout(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (i, subview) in subviews.enumerated() {
            subview.place(
                at: CGPoint(x: bounds.minX + result.frames[i].minX, y: bounds.minY + result.frames[i].minY),
                proposal: .unspecified
            )
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (frames: [CGRect], size: CGSize) {
        let maxW = proposal.replacingUnspecifiedDimensions().width
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowH: CGFloat = 0
        var frames: [CGRect] = []
        for sub in subviews {
            let sz = sub.sizeThatFits(.unspecified)
            if x + sz.width > maxW, x > 0.5 {
                x = 0
                y += rowH + spacing
                rowH = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: sz))
            rowH = max(rowH, sz.height)
            x += sz.width + spacing
        }
        return (frames, CGSize(width: maxW, height: y + rowH))
    }
}

enum JobBoardSkillChipState {
    case match
    case partialMiss
    case miss
}

struct JobBoardSkillChip: View {
    let text: String
    let state: JobBoardSkillChipState

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: state == .match ? "checkmark" : "xmark")
                .font(.caption2.weight(.bold))
            Text(text)
                .font(.caption2)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .foregroundStyle(foreground)
        .background(background, in: Capsule())
    }

    private var foreground: Color {
        switch state {
        case .match: return .green
        case .partialMiss: return .orange
        case .miss: return .red
        }
    }

    private var background: Color {
        foreground.opacity(0.12)
    }
}
