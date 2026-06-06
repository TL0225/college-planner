// AddRoleSheet.swift
// Feature: Career
// Purpose: Career module — AddRoleSheet.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI
import CollegeCareer

// MARK: - Add Role sheet

struct AddRoleSheet: View {
    @Environment(AppContainer.self) private var container
    private var persistence: CollegePersistence { container.persistence }
    @Environment(\.dismiss) private var dismiss
    private var collegePersistence: CollegePersistence { container.persistence }
    @State private var stage: CareerApplicationStatus = .interested
    @State private var jobTitle: String = ""
    @State private var company: String = ""
    @State private var location: String = ""
    @State private var compensation: String = ""
    @State private var tags: String = ""
    @State private var deadline: Date = Date()
    @State private var priority: CareerKanbanTheme.Priority = .medium
    @State private var notes: String = ""

    private var canSave: Bool {
        !jobTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !company.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                Text("Add New Role")
                    .font(.title2.bold())
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(6)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
            .padding(.bottom, 20)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    FormSection(title: "STAGE") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(CareerApplicationStatus.allCases, id: \.self) { status in
                                    CareerLaneStatusPill(status: status, isSelected: stage == status) {
                                        stage = status
                                    }
                                }
                            }
                        }
                    }

                    HStack(alignment: .top, spacing: 16) {
                        CustomTextField(label: "Job Title", isRequired: true, text: $jobTitle, placeholder: "Software Engineer")
                        CustomTextField(label: "Company", isRequired: true, text: $company, placeholder: "Google")
                    }

                    HStack(alignment: .top, spacing: 16) {
                        CustomTextField(label: "Location", isRequired: false, text: $location, placeholder: "Remote / NYC")
                        CustomTextField(label: "Compensation", isRequired: false, text: $compensation, placeholder: "$45/hr")
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        CustomTextField(label: "Skills / Tags", isRequired: false, text: $tags, placeholder: "Python, React, Internship")
                        Text("Comma separated")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Application Deadline")
                            .font(.subheadline.weight(.semibold))
                        DatePicker("", selection: $deadline, displayedComponents: .date)
                            .labelsHidden()
                            .datePickerStyle(.field)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Priority")
                            .font(.subheadline.weight(.semibold))
                        HStack(spacing: 12) {
                            ForEach(CareerKanbanTheme.Priority.allCases, id: \.self) { p in
                                CareerAddRolePriorityPill(priority: p, isSelected: priority == p) {
                                    priority = p
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Notes")
                            .font(.subheadline.weight(.semibold))
                        TextEditor(text: $notes)
                            .font(.body)
                            .frame(minHeight: 100)
                            .padding(8)
                            .scrollContentBackground(.hidden)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1)
                            )
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.secondary.opacity(0.04))
                            )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 12) {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)

                Button("Add Role") {
                    saveRole()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
            .padding(.top, 20)
        }
        .padding(24)
        .frame(width: 520)
        .frame(minHeight: 560)
    }

    private func saveRole() {
        let title = jobTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let co = company.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !co.isEmpty else { return }

        let keywords = tags
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let keywordsJSON = (try? String(data: JSONEncoder().encode(keywords), encoding: .utf8)) ?? "[]"

        let notesTrimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let loc = location.trimmingCharacters(in: .whitespacesAndNewlines)
        let pay = compensation.trimmingCharacters(in: .whitespacesAndNewlines)

        let app = collegePersistence.addCareerApplication(
            title: title,
            company: co,
            postingURLString: "",
            jobDescriptionText: notesTrimmed,
            interviewStatus: "",
            applicationDeadline: deadline,
            status: stage,
            extractedKeywordsJSON: keywordsJSON,
            locationText: loc.isEmpty ? nil : loc,
            baseSalaryText: pay.isEmpty ? nil : pay
        )
        collegePersistence.setCareerPriority(priority, for: app)
        CareerFollowUpScheduler.shared.reconcile(using: collegePersistence)
        dismiss()
    }
}

// MARK: - Helper components

struct FormSection<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            content
        }
    }
}

struct CustomTextField: View {
    let label: String
    var isRequired: Bool = false
    @Binding var text: String
    let placeholder: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 2) {
                Text(label)
                    .font(.subheadline.weight(.semibold))
                if isRequired {
                    Text("*")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.red)
                }
            }
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.22), lineWidth: 1)
                )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CareerLaneStatusPill: View {
    let status: CareerApplicationStatus
    let isSelected: Bool
    let action: () -> Void

    private var accent: Color {
        CareerKanbanTheme.laneAccent(for: status)
    }

    var body: some View {
        Button(action: action) {
            Text(status.displayName)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .foregroundStyle(isSelected ? Color.white : accent)
                .background(isSelected ? accent : Color.clear, in: Capsule(style: .continuous))
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(accent.opacity(isSelected ? 0 : 0.55), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

struct CareerAddRolePriorityPill: View {
    let priority: CareerKanbanTheme.Priority
    let isSelected: Bool
    let action: () -> Void

    private var label: String {
        switch priority {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        }
    }

    var body: some View {
        let style = CareerKanbanTheme.priorityPill(priority)
        Button(action: action) {
            HStack(spacing: 6) {
                Circle()
                    .fill(dotFill(style: style))
                    .frame(width: 6, height: 6)
                Text(label)
                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .foregroundStyle(isSelected ? style.foreground : labelColor)
            .background(isSelected ? style.background : Color.clear, in: Capsule(style: .continuous))
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(strokeColor(style: style), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var labelColor: Color {
        switch priority {
        case .high: return Color.red.opacity(0.92)
        case .medium: return Color.orange.opacity(0.95)
        case .low: return Color.secondary
        }
    }

    private func dotFill(style: CareerKanbanTheme.PillStyle) -> Color {
        if isSelected { return style.foreground }
        switch priority {
        case .high: return Color.red.opacity(0.85)
        case .medium: return Color.orange.opacity(0.85)
        case .low: return Color.secondary.opacity(0.65)
        }
    }

    private func strokeColor(style: CareerKanbanTheme.PillStyle) -> Color {
        if isSelected {
            switch priority {
            case .high, .medium:
                return style.background.opacity(0.45)
            case .low:
                return Color.secondary.opacity(0.22)
            }
        }
        switch priority {
        case .high: return Color.red.opacity(0.45)
        case .medium: return Color.orange.opacity(0.45)
        case .low: return Color.secondary.opacity(0.35)
        }
    }
}
