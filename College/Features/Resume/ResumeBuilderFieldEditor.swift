// ResumeBuilderFieldEditor.swift
// Feature: Resume
// Purpose: Inline field forms for the selected resume category.

import SwiftUI

struct ResumeBuilderFieldEditor: View {
    @Bindable var viewModel: ResumeBuilderViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            editorHeader

            Divider().opacity(0.35)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    editorBody
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
        }
        .background(DesignSystem.Colors.bgMain)
    }

    private var editorHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: viewModel.selectedCategory.systemImage)
                .foregroundStyle(DesignSystem.Colors.primary)
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.selectedCategory.title)
                    .font(.headline)
                Text(viewModel.selectedCategory.isProfileSourced
                    ? "Edits here apply to this resume only."
                    : "Resume-only content — not stored in Profile.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if viewModel.selectedCategory.isProfileSourced, viewModel.selectedCategory != .personal {
                Button("Add in Profile") {
                    openProfile()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var editorBody: some View {
        switch viewModel.selectedCategory {
        case .personal:
            personalEditor
        case .summary:
            summaryEditor
        case .education:
            educationEditor
        case .experience:
            experienceEditor
        case .projects:
            projectsEditor
        case .skills:
            skillsEditor
        case .achievements:
            achievementsEditor
        case .certifications:
            certificationsEditor
        case .extracurriculars:
            extracurricularsEditor
        }
    }

    // MARK: - Personal

    private var personalEditor: some View {
        let snap = viewModel.snapshot.personal
        return VStack(alignment: .leading, spacing: 12) {
            fieldRow("Full name", text: binding(.personal(.name), default: snap.name))
            fieldRow("Pronouns", text: binding(.personal(.pronouns), default: snap.pronouns ?? ""))
            fieldRow("Email", text: binding(.personal(.email), default: snap.email ?? ""))
            fieldRow("Phone", text: binding(.personal(.phone), default: snap.phone ?? ""))
            fieldRow("Address", text: binding(.personal(.address), default: snap.address ?? ""))

            if !snap.contactLinks.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Links")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(snap.contactLinks, id: \.url) { link in
                        Text(link.displayLabel)
                            .font(.subheadline)
                            .foregroundStyle(DesignSystem.Colors.primary)
                    }
                }
            }
        }
    }

    // MARK: - Summary

    private var summaryEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Professional Summary")
                .font(.subheadline.weight(.semibold))
            TextEditor(text: binding(.summary, default: viewModel.snapshot.summary ?? ""))
                .font(.body)
                .frame(minHeight: 140)
                .padding(8)
                .background(DesignSystem.Colors.surface, in: RoundedRectangle(cornerRadius: 10))
            Text("2–4 sentences highlighting your background and goals.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - List sections

    private var educationEditor: some View {
        listSection(
            entries: viewModel.snapshot.education,
            section: .education,
            emptyMessage: ResumeSectionKind.education.emptySectionMessage
        ) { entry in
            VStack(alignment: .leading, spacing: 8) {
                fieldRow("Degree", text: binding(.education(entry.id, .degreeLevel), default: entry.degreeLevel ?? ""))
                fieldRow("Major", text: binding(.education(entry.id, .major), default: entry.major ?? ""))
                fieldRow("School", text: binding(.education(entry.id, .collegeName), default: entry.collegeName ?? ""))
                fieldRow("Graduation", text: binding(.education(entry.id, .expectedGraduation), default: entry.expectedGraduation ?? ""))
                if let gpa = entry.gpa {
                    fieldRow("GPA", text: binding(.education(entry.id, .gpa), default: String(format: "%.2f", gpa)))
                }
            }
        }
    }

    private var experienceEditor: some View {
        listSection(
            entries: viewModel.snapshot.experiences,
            section: .experience,
            emptyMessage: ResumeSectionKind.experience.emptySectionMessage
        ) { entry in
            VStack(alignment: .leading, spacing: 8) {
                fieldRow("Title", text: binding(.experience(entry.id, .title), default: entry.title))
                fieldRow("Company", text: binding(.experience(entry.id, .company), default: entry.company))
                fieldRow("Location", text: binding(.experience(entry.id, .location), default: entry.location ?? ""))
                fieldRow("Dates", text: binding(.experience(entry.id, .dateRange), default: entry.dateRange))
                multilineField(
                    "Description",
                    text: binding(.experience(entry.id, .descriptionText), default: entry.descriptionText ?? "")
                )
                fieldRow("Technologies", text: binding(.experience(entry.id, .technologies), default: entry.technologies ?? ""))
            }
        }
    }

    private var projectsEditor: some View {
        listSection(
            entries: viewModel.snapshot.projects,
            section: .projects,
            emptyMessage: ResumeSectionKind.projects.emptySectionMessage
        ) { entry in
            VStack(alignment: .leading, spacing: 8) {
                fieldRow("Title", text: binding(.project(entry.id, .title), default: entry.title))
                fieldRow("Role", text: binding(.project(entry.id, .role), default: entry.role ?? ""))
                fieldRow("Dates", text: binding(.project(entry.id, .dateRange), default: entry.dateRange ?? ""))
                multilineField(
                    "Summary",
                    text: binding(.project(entry.id, .summary), default: entry.summary ?? "")
                )
                if !entry.bullets.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Bullets")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ForEach(entry.bullets, id: \.self) { bullet in
                            Text("• \(bullet)")
                                .font(.caption)
                        }
                    }
                }
            }
        }
    }

    private var skillsEditor: some View {
        Group {
            if viewModel.snapshot.skills.isEmpty {
                emptyState(ResumeSectionKind.skills)
            } else {
                Text(viewModel.snapshot.skills.joined(separator: ", "))
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var achievementsEditor: some View {
        listSection(
            entries: viewModel.snapshot.achievements,
            section: .achievements,
            emptyMessage: ResumeSectionKind.achievements.emptySectionMessage
        ) { entry in
            VStack(alignment: .leading, spacing: 8) {
                fieldRow("Award", text: binding(.achievement(entry.id, .name), default: entry.name ?? ""))
                fieldRow("Organization", text: binding(.achievement(entry.id, .organization), default: entry.organization ?? ""))
                fieldRow("Date", text: binding(.achievement(entry.id, .dateReceived), default: entry.dateReceived ?? ""))
                multilineField(
                    "Description",
                    text: binding(.achievement(entry.id, .descriptionText), default: entry.descriptionText ?? "")
                )
            }
        }
    }

    private var certificationsEditor: some View {
        let items = certificationItems
        return VStack(alignment: .leading, spacing: 12) {
            if items.isEmpty {
                emptyState(.certifications)
            } else {
                ForEach(Array(items.enumerated()), id: \.offset) { index, _ in
                    fieldRow("Certification \(index + 1)", text: certificationBinding(index: index))
                }
            }
            Button {
                viewModel.addCertification()
            } label: {
                Label("Add certification", systemImage: "plus.circle")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private var extracurricularsEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            listSection(
                entries: viewModel.snapshot.extracurriculars,
                section: .extracurriculars,
                emptyMessage: ResumeSectionKind.extracurriculars.emptySectionMessage
            ) { entry in
                VStack(alignment: .leading, spacing: 8) {
                    fieldRow("Organization", text: binding(.extracurricular(entry.id, .organization), default: entry.organization))
                    fieldRow("Role", text: binding(.extracurricular(entry.id, .role), default: entry.role ?? ""))
                    fieldRow("Dates", text: binding(.extracurricular(entry.id, .dateRange), default: entry.dateRange ?? ""))
                    multilineField(
                        "Description",
                        text: binding(.extracurricular(entry.id, .descriptionText), default: entry.descriptionText ?? "")
                    )
                }
            }
            Button {
                viewModel.addExtracurricular()
            } label: {
                Label("Add activity", systemImage: "plus.circle")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    // MARK: - Helpers

    private var certificationItems: [String] {
        let snap = viewModel.snapshot.certifications
        let overrideCount = viewModel.document.fieldOverrides.keys
            .filter { $0.hasPrefix("certification.") }
            .compactMap { Int($0.replacingOccurrences(of: "certification.", with: "")) }
        let maxIndex = max((overrideCount.max() ?? -1), snap.count - 1)
        guard maxIndex >= 0 else { return [] }
        return (0...maxIndex).map { index in
            viewModel.fieldValue(
                for: .certification(index),
                default: index < snap.count ? snap[index] : ""
            )
        }
    }

    private func certificationBinding(index: Int) -> Binding<String> {
        let snap = viewModel.snapshot
        let defaultValue = index < snap.certifications.count ? snap.certifications[index] : ""
        return binding(.certification(index), default: defaultValue)
    }

    private func binding(_ key: ResumeFieldKey, default defaultValue: String) -> Binding<String> {
        Binding(
            get: {
                viewModel.fieldValue(for: key, default: defaultValue)
            },
            set: { newValue in
                viewModel.setFieldOverride(newValue, for: key)
            }
        )
    }

    @ViewBuilder
    private func listSection<Entry: Identifiable, Content: View>(
        entries: [Entry],
        section: ResumeSectionKind,
        emptyMessage: String,
        @ViewBuilder content: @escaping (Entry) -> Content
    ) -> some View where Entry.ID == UUID {
        if entries.isEmpty {
            emptyStateMessage(emptyMessage)
        } else {
            ForEach(entries) { entry in
                VStack(alignment: .leading, spacing: 8) {
                    content(entry)
                }
                .padding(12)
                .background(DesignSystem.Colors.surface, in: RoundedRectangle(cornerRadius: 10))
                .draggable(ResumeEntryDragItem(section: section, entryID: entry.id))
                .dropDestination(for: ResumeEntryDragItem.self) { items, _ in
                    guard let incoming = items.first, incoming.section == section else { return false }
                    viewModel.placeEntry(incoming.entryID, in: section, before: entry.id)
                    return true
                }
            }
        }
    }

    private func fieldRow(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField(title, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func multilineField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            TextEditor(text: text)
                .font(.body)
                .frame(minHeight: 90)
                .padding(6)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                )
        }
    }

    private func emptyState(_ kind: ResumeSectionKind) -> some View {
        emptyStateMessage(kind.emptySectionMessage)
    }

    private func emptyStateMessage(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No entries yet")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func openProfile() {
        AppTypedNavigationRouter.openPage(.profile)
        NSApp.activate(ignoringOtherApps: true)
    }
}
