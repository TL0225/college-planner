// ResumeAutofillReviewSheet.swift
// Feature: Career / Resumes
// Purpose: Review-and-confirm sheet for importing parsed resume data into Profile.

import SwiftUI

struct ResumeAutofillReviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppContainer.self) private var container

    let diff: ProfileAutofillDiff
    var onApplied: () -> Void = {}

    @State private var selection: ProfileAutofillSelection

    private var collegePersistence: CollegePersistence { container.persistence }
    private var notifications: AppNotificationCenter { container.appNotifications }

    init(diff: ProfileAutofillDiff, onApplied: @escaping () -> Void = {}) {
        self.diff = diff
        self.onApplied = onApplied
        _selection = State(initialValue: .noneEnabled)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Import to Profile")
                .font(.title2.weight(.semibold))

            Text("Choose which resume fields to copy into your profile. Nothing is imported until you confirm below.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if diff.isEmpty {
                Text("Nothing new to import — your profile already has these resume fields.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                List {
                    ForEach(groupedScalarSections, id: \.section) { group in
                        Section(group.section) {
                            ForEach(group.items) { item in
                                autofillToggleRow(
                                    title: item.label,
                                    subtitle: item.proposedValue,
                                    isOn: scalarBinding(for: item.id)
                                )
                            }
                        }
                    }

                    if !diff.experiences.isEmpty {
                        Section("Experience") {
                            ForEach(diff.experiences) { entry in
                                autofillToggleRow(
                                    title: "\(entry.title) at \(entry.company)",
                                    subtitle: entry.descriptionText,
                                    isOn: experienceBinding(for: entry.id)
                                )
                            }
                        }
                    }

                    if !diff.projects.isEmpty {
                        Section("Projects") {
                            ForEach(diff.projects) { entry in
                                autofillToggleRow(
                                    title: entry.project.title,
                                    subtitle: entry.project.summary,
                                    isOn: projectBinding(for: entry.id)
                                )
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Apply Selected") { applySelected() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!hasAnySelection)
            }
        }
        .padding(DesignSystem.Spacing.xl)
        .frame(minWidth: 520, minHeight: 480)
    }

    private var groupedScalarSections: [(section: String, items: [ScalarAutofillItem])] {
        let grouped = Dictionary(grouping: diff.scalarItems, by: \.section)
        return grouped.keys.sorted().map { key in
            (section: key, items: grouped[key] ?? [])
        }
    }

    private var hasAnySelection: Bool {
        !selection.enabledScalarFields.isEmpty
            || !selection.enabledExperienceIDs.isEmpty
            || !selection.enabledProjectIDs.isEmpty
    }

    private func scalarBinding(for id: ProfileAutofillFieldID) -> Binding<Bool> {
        Binding(
            get: { selection.enabledScalarFields.contains(id) },
            set: { enabled in
                if enabled {
                    selection.enabledScalarFields.insert(id)
                } else {
                    selection.enabledScalarFields.remove(id)
                }
            }
        )
    }

    private func experienceBinding(for id: String) -> Binding<Bool> {
        Binding(
            get: { selection.enabledExperienceIDs.contains(id) },
            set: { enabled in
                if enabled {
                    selection.enabledExperienceIDs.insert(id)
                } else {
                    selection.enabledExperienceIDs.remove(id)
                }
            }
        )
    }

    private func projectBinding(for id: String) -> Binding<Bool> {
        Binding(
            get: { selection.enabledProjectIDs.contains(id) },
            set: { enabled in
                if enabled {
                    selection.enabledProjectIDs.insert(id)
                } else {
                    selection.enabledProjectIDs.remove(id)
                }
            }
        )
    }

    @ViewBuilder
    private func autofillToggleRow(title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body.weight(.medium))
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }
        }
        .toggleStyle(.checkbox)
    }

    private func applySelected() {
        CareerResumeProfileAutofillService.apply(
            diff,
            selection: selection,
            using: collegePersistence
        )
        notifications.post(
            kind: .success,
            title: "Profile updated",
            message: "Imported selected resume fields into your profile.",
            isDismissible: true,
            autoDismissAfter: 4
        )
        onApplied()
        dismiss()
    }
}
