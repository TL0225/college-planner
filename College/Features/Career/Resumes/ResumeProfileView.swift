// ResumeProfileView.swift
// Feature: Career / Resumes
// Purpose: Full-screen parsed resume profile (Jobright-style drill-down).

import AppKit
import SwiftUI

struct ResumeProfileView: View {
    @Environment(AppContainer.self) private var appContainer

    let resume: VaultDocument
    let onClose: () -> Void
    let onReingest: () -> Void
    let onExport: () -> Void
    let onDelete: () -> Void
    let onImportToProfile: () -> Void
    let onOpenJob: (UUID) -> Void

    @ObservedObject private var ingestProgressStore = CareerResumeIngestProgressStore.shared
    @State private var showEditInfo = false
    @State private var showParserReport = false
    @State private var showParseReview = false
    @State private var editDisplayName = ""
    @State private var editTargetRole = ""

    private var collegePersistence: CollegePersistence { appContainer.persistence }
    private var meta: CareerResumeMetadataV1 { collegePersistence.careerResumeMetadata(for: resume) }
    private var profile: CareerResumeStructuredProfile? { meta.structuredProfile }
    private var isIngesting: Bool { meta.ingestCompletedAt == nil }

    private var displayTitle: String {
        let raw = resume.customDisplayName ?? resume.fileName
        return raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Resume" : raw
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                profileToolbar
                scoreSection
                personalSection
                linkCardsSection

                if let profile {
                    if !profile.education.isEmpty {
                        profileSection(title: "Education") {
                            educationContent(profile)
                        }
                    }
                    if !profile.experience.isEmpty {
                        profileSection(title: "Work experience") {
                            experienceContent(profile)
                        }
                    }
                    if !profile.projects.isEmpty {
                        profileSection(title: "Projects") {
                            timelineContent(profile.projects, style: .project)
                        }
                    }
                    if !profile.skills.isEmpty || !profile.skillGroups.isEmpty {
                        profileSection(title: "Skills") {
                            skillsContent(profile)
                        }
                    }
                    if let summary = profile.summary, !summary.isEmpty {
                        profileSection(title: "Summary") {
                            Text(summary)
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                } else if isIngesting {
                    ingestProgressCard
                } else {
                    ContentUnavailableView {
                        Label("No profile yet", systemImage: "doc.text.magnifyingglass")
                    } description: {
                        Text("Re-analyze this resume to extract structured fields.")
                    } actions: {
                        Button("Re-analyze", action: onReingest)
                            .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, minHeight: 220)
                }

                linkedJobsSection
            }
            .padding(24)
            .frame(maxWidth: 920, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(DesignSystem.Colors.bgMain)
        .sheet(isPresented: $showEditInfo) { editInfoSheet }
        .sheet(isPresented: $showParserReport) { parserReportSheet }
        .sheet(isPresented: $showParseReview) { parseReviewSheet }
        .onAppear {
            collegePersistence.markVaultDocumentOpened(resume)
            editDisplayName = resume.customDisplayName ?? resume.fileName
            editTargetRole = meta.targetRole ?? ""
        }
    }

    // MARK: - Toolbar

    private var profileToolbar: some View {
        HStack(spacing: 12) {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .background(Color.secondary.opacity(0.10), in: Circle())
            }
            .buttonStyle(.plain)
            .help("Back to resume list")

            HStack(spacing: 8) {
                if resume.isFavorite {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                }
                Text(displayTitle)
                    .font(.headline.weight(.semibold))
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.secondary.opacity(0.08), in: Capsule(style: .continuous))

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                if profile != nil {
                    Button("Review parsed fields") { showParseReview = true }
                        .buttonStyle(.bordered)

                    Button("Import to Profile", action: onImportToProfile)
                        .buttonStyle(.bordered)
                }

                Button("Edit Info") { showEditInfo = true }
                    .buttonStyle(.bordered)

                Button("Export", action: onExport)
                    .buttonStyle(.bordered)

                Button("Delete", role: .destructive, action: onDelete)
                    .buttonStyle(.bordered)
            }
        }
    }

    // MARK: - Score

    private var scoreSection: some View {
        let issues = parserIssues
        let warnings = issues.filter { $0.severity == .warning }.count
        let critical = issues.filter { $0.severity == .critical }.count
        let stale = staleSkillCount
        let accent = CareerResumeLibraryTheme.accent(for: meta.kind)

        return HStack(alignment: .center, spacing: 20) {
            Text(ResumeProfileScoring.letterGrade(for: meta.parserHealthPercent))
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(accent)
                .frame(width: 64, height: 64)
                .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(ResumeProfileScoring.ratingLabel(for: meta.parserHealthPercent))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ResumeProfileScoring.ratingColor(for: meta.parserHealthPercent))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            ResumeProfileScoring.ratingColor(for: meta.parserHealthPercent).opacity(0.12),
                            in: Capsule(style: .continuous)
                        )

                    Button("Parser report") { showParserReport = true }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 10) {
                    issueCounter(count: warnings, label: "Warnings", tint: .orange)
                    issueCounter(count: critical, label: "Critical", tint: DesignSystem.Colors.error)
                    issueCounter(count: stale, label: "Stale skills", tint: .secondary)
                }
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 8) {
                Button("Re-analyze", action: onReingest)
                    .buttonStyle(.borderedProminent)
                    .disabled(isIngesting)

                if let scoredAt = meta.parserScoredAt ?? meta.ingestCompletedAt {
                    Text("Updated \(relativeDate(scoredAt))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(DesignSystem.Spacing.lg)
        .background(DesignSystem.Colors.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private func issueCounter(count: Int, label: String, tint: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(count)")
                .font(.title3.weight(.bold))
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 72)
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - Personal

    private var personalSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(profile?.name ?? displayTitle)
                .font(.largeTitle.weight(.bold))

            HStack(spacing: 0) {
                contactColumn(icon: "envelope", label: "Email", value: profile?.email)
                contactColumn(icon: "phone", label: "Phone", value: profile?.phone)
                contactColumn(icon: "mappin.and.ellipse", label: "Location", value: profile?.location)
            }
        }
    }

    private func contactColumn(icon: String, label: String, value: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(label, systemImage: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value?.isEmpty == false ? value! : "—")
                .font(.body.weight(.medium))
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Links

    @ViewBuilder
    private var linkCardsSection: some View {
        let links = parsedLinks
        if !links.isEmpty {
            HStack(spacing: 12) {
                ForEach(links.indices, id: \.self) { idx in
                    linkCard(links[idx])
                }
            }
        }
    }

    private struct ParsedLink: Identifiable {
        let id = UUID()
        let kind: String
        let icon: String
        let url: String
    }

    private var parsedLinks: [ParsedLink] {
        guard let profile else { return [] }
        var result: [ParsedLink] = []
        var linkedIn: String?
        var github: String?
        var other: String?

        for link in profile.links {
            let lower = link.lowercased()
            if lower.contains("linkedin"), linkedIn == nil {
                linkedIn = link
            } else if lower.contains("github"), github == nil {
                github = link
            } else if other == nil {
                other = link
            }
        }

        if let linkedIn { result.append(.init(kind: "LinkedIn", icon: "link", url: linkedIn)) }
        if let github { result.append(.init(kind: "GitHub", icon: "chevron.left.forwardslash.chevron.right", url: github)) }
        if let other { result.append(.init(kind: "Other", icon: "globe", url: other)) }
        return result
    }

    private func linkCard(_ link: ParsedLink) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(link.kind, systemImage: link.icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(link.url)
                .font(.caption)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Sections

    private func profileSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(DesignSystem.Colors.textLight)
                .tracking(0.3)
            content()
        }
    }

    private func educationContent(_ profile: CareerResumeStructuredProfile) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(profile.education.indices, id: \.self) { idx in
                let fields = CareerResumeParsedEntryDisplay.educationFields(from: profile.education[idx])
                VStack(alignment: .leading, spacing: 10) {
                    Text(fields.institution)
                        .font(.title3.weight(.semibold))
                    if let degree = fields.degree {
                        profileFieldRow(label: "Degree", value: degree)
                    }
                    if let graduation = fields.graduation {
                        profileFieldRow(label: "Graduation", value: graduation)
                    }
                    if let gpa = fields.gpa {
                        profileFieldRow(label: "GPA", value: gpa)
                    }
                    ForEach(fields.extras, id: \.self) { extra in
                        profileFieldRow(label: "Detail", value: extra)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private func experienceContent(_ profile: CareerResumeStructuredProfile) -> some View {
        timelineContent(profile.experience, style: .experience)
    }

    private enum TimelineStyle { case experience, project }

    private func timelineContent(_ entries: [CareerResumeStructuredProfile.Entry], style: TimelineStyle) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(entries.indices, id: \.self) { idx in
                let display: CareerResumeParsedEntryDisplay = {
                    switch style {
                    case .experience: return .experience(from: entries[idx])
                    case .project: return .project(from: entries[idx])
                    }
                }()
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(display.title)
                            .font(.headline)
                        Spacer()
                        if let dateLabel = display.dateLabel {
                            Text(dateLabel)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let org = display.organization {
                        Text(org)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(display.bullets, id: \.self) { bullet in
                        HStack(alignment: .top, spacing: 8) {
                            Text("•")
                            Text(bullet)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private func skillsContent(_ profile: CareerResumeStructuredProfile) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if !profile.skillGroups.isEmpty {
                ForEach(profile.skillGroups.indices, id: \.self) { idx in
                    let group = profile.skillGroups[idx]
                    VStack(alignment: .leading, spacing: 6) {
                        Text(group.category)
                            .font(.subheadline.weight(.semibold))
                        Text(group.skills.joined(separator: " · "))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text(profile.skills.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func profileFieldRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    // MARK: - Linked jobs

    @ViewBuilder
    private var linkedJobsSection: some View {
        if let linked = resume.submittedApplications, !linked.isEmpty {
            profileSection(title: "Linked jobs") {
                VStack(spacing: 8) {
                    ForEach(Array(linked).sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }, id: \.id) { app in
                        Button {
                            onOpenJob(app.id)
                        } label: {
                            HStack {
                                Text("\(app.company ?? "Company") · \(app.title ?? "Role")")
                                    .font(.subheadline)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(12)
                            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Ingest progress

    @ViewBuilder
    private var ingestProgressCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let progress = ingestProgressStore.progress(for: resume.id) {
                ProgressView(value: progress.fraction)
                Text(progress.stageLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
                Text("Reading your resume and organizing sections with on-device AI…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Sheets

    private var editInfoSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit Resume Info")
                .font(.title3.weight(.semibold))

            VStack(alignment: .leading, spacing: 6) {
                Text("Display name")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField("Resume name", text: $editDisplayName)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Target job title")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField("e.g. Security Analyst", text: $editTargetRole)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Spacer()
                Button("Cancel") { showEditInfo = false }
                Button("Save") {
                    collegePersistence.renameVaultDocument(resume, newName: editDisplayName)
                    var updated = collegePersistence.careerResumeMetadata(for: resume)
                    let trimmed = editTargetRole.trimmingCharacters(in: .whitespacesAndNewlines)
                    updated.targetRole = trimmed.isEmpty ? nil : trimmed
                    try? collegePersistence.setCareerResumeMetadata(updated, for: resume)
                    showEditInfo = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 420)
    }

    private var parserReportSheet: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Parser Report")
                    .font(.title3.weight(.semibold))

                if parserIssues.isEmpty {
                    Text("No parser issues detected.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(parserIssues.indices, id: \.self) { idx in
                        let issue = parserIssues[idx]
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: issue.severity == .critical ? "exclamationmark.triangle.fill" : "info.circle")
                                .foregroundStyle(issue.severity == .critical ? .red : .orange)
                            Text(issue.message)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                if !detectedDomains.isEmpty {
                    Text("Detected domains")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                    Text(detectedDomains.joined(separator: ", "))
                        .font(.subheadline)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 480, height: 360)
    }

    @ViewBuilder
    private var parseReviewSheet: some View {
        if let profile {
            NavigationStack {
                ResumeParsedProfileTabbedView(profile: profile)
                    .navigationTitle("Parsed resume fields")
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showParseReview = false }
                        }
                    }
            }
            .frame(minWidth: 560, minHeight: 520)
        }
    }

    // MARK: - Helpers

    private var parserIssues: [ParserComplianceIssue] {
        guard let json = meta.parserIssuesJSON,
              let data = json.data(using: .utf8),
              let issues = try? JSONDecoder().decode([ParserComplianceIssue].self, from: data)
        else { return [] }
        return issues
    }

    private var staleSkillCount: Int {
        guard let json = meta.staleSkillsJSON,
              let data = json.data(using: .utf8),
              let stale = try? JSONDecoder().decode([CareerStaleSkillWarning].self, from: data)
        else { return 0 }
        return stale.count
    }

    private var detectedDomains: [String] {
        guard let json = meta.detectedDomainsJSON,
              let data = json.data(using: .utf8),
              let domains = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return domains
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
