// ResumeParsedProfileTabbedView.swift
// Feature: Career / ResumeParsing
// Purpose: Jobright-style tabbed review of parsed resume fields before profile import.

import SwiftUI

struct ResumeParsedProfileTabbedView: View {
    let profile: CareerResumeStructuredProfile

    @State private var selectedTab: Tab = .personal

    private enum Tab: String, CaseIterable, Identifiable {
        case personal
        case education
        case experience
        case projects
        case skills

        var id: String { rawValue }

        var title: String {
            switch self {
            case .personal: return "Personal"
            case .education: return "Education"
            case .experience: return "Work"
            case .projects: return "Projects"
            case .skills: return "Skills"
            }
        }

        var icon: String {
            switch self {
            case .personal: return "person.crop.circle"
            case .education: return "graduationcap"
            case .experience: return "briefcase"
            case .projects: return "folder"
            case .skills: return "sparkles"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Section", selection: $selectedTab) {
                ForEach(Tab.allCases) { tab in
                    Label(tab.title, systemImage: tab.icon).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Group {
                switch selectedTab {
                case .personal:
                    personalTab
                case .education:
                    educationTab
                case .experience:
                    experienceTab
                case .projects:
                    projectsTab
                case .skills:
                    skillsTab
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.easeInOut(duration: 0.15), value: selectedTab)
        }
    }

    // MARK: - Tabs

    @ViewBuilder
    private var personalTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let name = profile.name {
                labeledField("Name", value: name)
            }
            if let location = profile.location {
                labeledField("Location", value: location)
            }
            if let email = profile.email {
                labeledField("Email", value: email)
            }
            if let phone = profile.phone {
                labeledField("Phone", value: phone)
            }
            if !profile.links.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Links")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                    ForEach(profile.links.indices, id: \.self) { idx in
                        Text(profile.links[idx])
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
            if let summary = profile.summary, !summary.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Summary")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if profile.name == nil, profile.email == nil, profile.phone == nil,
               profile.location == nil, profile.links.isEmpty, profile.summary == nil {
                emptyTabMessage("No contact or summary fields detected.")
            }
        }
    }

    @ViewBuilder
    private var educationTab: some View {
        if profile.education.isEmpty {
            emptyTabMessage("No education entries detected.")
        } else {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(profile.education.indices, id: \.self) { idx in
                    structuredEducationCard(
                        CareerResumeParsedEntryDisplay.educationFields(from: profile.education[idx]),
                        isLast: idx == profile.education.count - 1
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func structuredEducationCard(
        _ fields: CareerResumeParsedEntryDisplay.EducationFields,
        isLast: Bool
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 0) {
                if let dateLabel = fields.dateLabel {
                    Text(dateLabel)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(width: 72)
                } else {
                    Color.clear.frame(width: 72, height: 1)
                }
                Circle()
                    .fill(Color.accentColor.opacity(0.85))
                    .frame(width: 7, height: 7)
                    .padding(.top, 4)
                if !isLast {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.18))
                        .frame(width: 1)
                        .frame(maxHeight: .infinity)
                        .padding(.top, 4)
                }
            }
            .frame(width: 72)

            VStack(alignment: .leading, spacing: 6) {
                Text(fields.institution)
                    .font(.caption.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)

                if let degree = fields.degree {
                    educationFieldRow(label: "Degree", value: degree)
                }
                if let graduation = fields.graduation {
                    educationFieldRow(label: "Graduation", value: graduation)
                }
                if let gpa = fields.gpa {
                    educationFieldRow(label: "GPA", value: gpa)
                }
                if let honors = fields.honors {
                    educationFieldRow(label: "Honors", value: honors)
                }
                if let coursework = fields.coursework {
                    educationFieldRow(label: "Coursework", value: coursework)
                }
                ForEach(fields.extras.indices, id: \.self) { idx in
                    parsedBulletRow(fields.extras[idx])
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func educationFieldRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var experienceTab: some View {
        if profile.experience.isEmpty {
            emptyTabMessage("No work experience detected.")
        } else {
            entryTimeline(profile.experience, style: .experience)
        }
    }

    @ViewBuilder
    private var projectsTab: some View {
        if profile.projects.isEmpty {
            emptyTabMessage("No projects detected.")
        } else {
            entryTimeline(profile.projects, style: .project)
        }
    }

    @ViewBuilder
    private var skillsTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !profile.skillGroups.isEmpty {
                ForEach(profile.skillGroups.indices, id: \.self) { idx in
                    let group = profile.skillGroups[idx]
                    VStack(alignment: .leading, spacing: 6) {
                        Text(group.category)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ResumeSkillChipFlow(tokens: group.skills)
                    }
                }
            } else if !profile.skills.isEmpty {
                ResumeSkillChipFlow(tokens: profile.skills)
            } else {
                emptyTabMessage("No skills detected.")
            }

            if !profile.certifications.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Certifications & awards")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(profile.certifications.indices, id: \.self) { idx in
                        parsedBulletRow(profile.certifications[idx])
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    // MARK: - Shared rendering

    private enum EntryStyle {
        case experience, project, education
    }

    @ViewBuilder
    private func entryTimeline(
        _ entries: [CareerResumeStructuredProfile.Entry],
        style: EntryStyle
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(entries.indices, id: \.self) { idx in
                let entry = entries[idx]
                let display: CareerResumeParsedEntryDisplay = {
                    switch style {
                    case .experience: return .experience(from: entry)
                    case .project: return .project(from: entry)
                    case .education: return .education(from: entry)
                    }
                }()
                if !display.title.isEmpty || !display.bullets.isEmpty {
                    timelineRow(display, style: style, isLast: idx == entries.count - 1)
                }
            }
        }
    }

    @ViewBuilder
    private func timelineRow(
        _ display: CareerResumeParsedEntryDisplay,
        style: EntryStyle,
        isLast: Bool
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 0) {
                if let dateLabel = display.dateLabel {
                    Text(dateLabel)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(width: 72)
                } else {
                    Color.clear.frame(width: 72, height: 1)
                }
                Circle()
                    .fill(Color.accentColor.opacity(0.85))
                    .frame(width: 7, height: 7)
                    .padding(.top, 4)
                if !isLast {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.18))
                        .frame(width: 1)
                        .frame(maxHeight: .infinity)
                        .padding(.top, 4)
                }
            }
            .frame(width: 72)

            VStack(alignment: .leading, spacing: 4) {
                if style == .experience, let organization = display.organization, !organization.isEmpty {
                    Text(organization)
                        .font(.caption.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(display.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(display.title)
                        .font(.caption.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    if let organization = display.organization, !organization.isEmpty {
                        Text(organization)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if let subtitle = display.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !display.bullets.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(display.bullets.indices, id: \.self) { bIdx in
                            parsedBulletRow(display.bullets[bIdx])
                        }
                    }
                    .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func labeledField(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private func emptyTabMessage(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func parsedBulletRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("•")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Skill chips

struct ResumeSkillChipFlow: View {
    let tokens: [String]

    var body: some View {
        ResumeFlexibleChipLayout(spacing: 6, lineSpacing: 6) {
            ForEach(tokens.indices, id: \.self) { idx in
                Text(tokens[idx])
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.12), in: Capsule())
            }
        }
    }
}

private struct ResumeFlexibleChipLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let maxWidth = bounds.width
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.minX + maxWidth {
                x = bounds.minX
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
