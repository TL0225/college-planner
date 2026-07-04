// NetworkingAddContactSheet.swift
// Feature: Career
// Purpose: Career module — NetworkingAddContactSheet.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI
import AppKit

@MainActor
struct NetworkingAddContactSheet: View {
    @Environment(AppContainer.self) private var container
    private var persistence: CollegePersistence { container.persistence }
    @Environment(\.dismiss) private var dismiss

    @State private var fullName: String = ""
    @State private var jobTitle: String = ""
    @State private var company: String = ""

    enum RelationshipType: String, CaseIterable {
        case recruiter = "Recruiter"
        case alumni = "Alumni"
        case referral = "Referral"
        case hiringMgr = "Hiring Mgr"
        case peer = "Peer"
    }
    @State private var relationship: RelationshipType = .recruiter

    @State private var connectedVia: String = ""
    @State private var tags: String = ""
    @State private var notes: String = ""

    @State private var hasFollowUp: Bool = false
    @State private var nextFollowUp: Date = Date()

    @FocusState private var focusedField: FormField?

    enum FormField {
        case fullName, jobTitle, company, connectedVia, tags, notes
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Add Contact")
                    .font(.title2.weight(.bold))
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    inputField(label: "Full Name *", text: $fullName, placeholder: "e.g. Sarah Chen")
                        .focused($focusedField, equals: .fullName)

                    HStack(spacing: 16) {
                        inputField(label: "Job Title", text: $jobTitle, placeholder: "e.g. Recruiter")
                            .focused($focusedField, equals: .jobTitle)
                        inputField(label: "Company *", text: $company, placeholder: "e.g. Google")
                            .focused($focusedField, equals: .company)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Relationship")
                            .font(.subheadline.weight(.semibold))

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100, maximum: 140))], spacing: 10) {
                            ForEach(RelationshipType.allCases, id: \.self) { type in
                                relationshipPill(for: type)
                            }
                        }
                    }

                    HStack(spacing: 16) {
                        inputField(label: "Connected Via", text: $connectedVia, placeholder: "LinkedIn, Email...")
                            .focused($focusedField, equals: .connectedVia)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Next Follow Up")
                                .font(.subheadline.weight(.semibold))

                            HStack {
                                Toggle("", isOn: $hasFollowUp)
                                    .labelsHidden()
                                    .toggleStyle(.checkbox)

                                if hasFollowUp {
                                    DatePicker("", selection: $nextFollowUp, displayedComponents: .date)
                                        .labelsHidden()
                                } else {
                                    Text("mm/dd/yyyy")
                                        .foregroundStyle(.tertiary)
                                }
                                Spacer()
                            }
                            .padding(DesignSystem.Spacing.md)
                            .frame(height: 38)
                            .background(controlFieldBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1))
                        }
                    }

                    inputField(label: "Tags", text: $tags, placeholder: "SWE, Referral, High Priority")
                        .focused($focusedField, equals: .tags)

                    notesField
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)

            VStack(spacing: 0) {
                Divider()
                HStack(spacing: 12) {
                    Spacer()
                    Button("Cancel") {
                        dismiss()
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.secondary.opacity(0.3)))

                    Button("Add Contact") {
                        saveContact()
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(isFormValid ? Color(red: 0.11, green: 0.11, blue: 0.12) : Color.gray.opacity(0.28))
                    .foregroundStyle(.white.opacity(isFormValid ? 1 : 0.75))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .disabled(!isFormValid)
                    .keyboardShortcut(.defaultAction)
                }
                .padding(DesignSystem.Spacing.lg)
                .background(sheetChromeBackground)
            }
        }
        .frame(width: 480, height: 560)
        .onAppear {
            focusedField = .fullName
        }
    }

    private var isFormValid: Bool {
        !fullName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !company.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func saveContact() {
        guard isFormValid else { return }

        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTags = tags.trimmingCharacters(in: .whitespacesAndNewlines)
        let summary: String?
        if trimmedTags.isEmpty {
            summary = optionalTrimmed(notes)
        } else if trimmedNotes.isEmpty {
            summary = "Tags: \(trimmedTags)"
        } else {
            summary = "Tags: \(trimmedTags)\n\n\(trimmedNotes)"
        }

        do {
            _ = try persistence.careerRepository.createOrphanRecruiterContact(
                fullName: fullName.trimmingCharacters(in: .whitespacesAndNewlines),
                roleTitle: optionalTrimmed(jobTitle),
                companyName: company.trimmingCharacters(in: .whitespacesAndNewlines),
                contactKindRaw: relationship.rawValue,
                lastInteractionChannelRaw: optionalTrimmed(connectedVia),
                lastInteractionSummary: summary,
                followUpDate: hasFollowUp ? nextFollowUp : nil
            )
            dismiss()
        } catch {
            #if DEBUG
            print("[NetworkingAddContactSheet] save failed: \(error)")
            #endif
        }
    }

    private func optionalTrimmed(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var sheetChromeBackground: Color {
        DesignSystem.Colors.surface
    }

    private var controlFieldBackground: Color {
        Color.secondary.opacity(0.06)
    }

    private func inputField(label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.subheadline.weight(.semibold))
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .padding(DesignSystem.Spacing.md)
                .frame(height: 38)
                .background(controlFieldBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1))
        }
    }

    private var notesField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Notes")
                .font(.subheadline.weight(.semibold))
            TextEditor(text: $notes)
                .font(.body)
                .frame(minHeight: 80)
                .padding(DesignSystem.Spacing.sm)
                .scrollContentBackground(.hidden)
                .background(controlFieldBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1))
                .focused($focusedField, equals: .notes)
        }
    }

    private func relationshipPill(for type: RelationshipType) -> some View {
        Button {
            relationship = type
        } label: {
            Text(type.rawValue)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(relationship == type ? Color.accentColor.opacity(0.15) : controlFieldBackground)
                .foregroundStyle(relationship == type ? Color.accentColor : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(relationship == type ? Color.accentColor.opacity(0.5) : Color.secondary.opacity(0.2), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}
