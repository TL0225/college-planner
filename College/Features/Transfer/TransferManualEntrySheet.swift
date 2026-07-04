// TransferManualEntrySheet.swift
// Feature: Transfer
// Purpose: Sheet form for adding a manual source→target equivalency.

import SwiftUI
import UniformTypeIdentifiers

struct TransferManualEntrySheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var draft: TransferManualEntryDraft
    @State private var validationMessage: String?
    @State private var proofPDFURL: URL?
    @State private var proofPDFFileName: String?
    @State private var showProofImporter = false
    @State private var isSaving = false
    let onSave: (TransferManualEntryDraft, URL?) async -> String?

    init(
        sourceSchoolName: String,
        defaultTargetSchoolName: String = "",
        onSave: @escaping (TransferManualEntryDraft, URL?) async -> String?
    ) {
        _draft = State(
            initialValue: TransferManualEntryDraft(
                sourceSchoolName: sourceSchoolName,
                targetSchoolName: defaultTargetSchoolName
            )
        )
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    schoolsSection
                    sourceCourseSection
                    targetCourseSection
                    mappingSection
                    optionalSection
                    proofUploadSection
                    if let validationMessage {
                        Text(validationMessage)
                            .font(.callout)
                            .foregroundStyle(.red)
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            footer
        }
        .frame(minWidth: 520, idealWidth: 580, minHeight: 520, idealHeight: 640)
        .background(DesignSystem.Colors.bgMain)
        .fileImporter(
            isPresented: $showProofImporter,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                proofPDFURL = url
                proofPDFFileName = url.lastPathComponent
            case .failure(let error):
                validationMessage = "Could not open PDF: \(error.localizedDescription)"
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Add Manual Equivalency")
                    .font(.title3.weight(.semibold))
                Text("Saved locally as unverified manual entry. Attach an official results PDF when available.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
                .disabled(isSaving)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    private var schoolsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Schools")
            formRow("Source school") {
                TextField("Community college or prior institution", text: $draft.sourceSchoolName)
                    .textFieldStyle(.roundedBorder)
            }
            formRow("Target school") {
                TextField("University you are transferring into", text: $draft.targetSchoolName)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private var sourceCourseSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Source course")
            HStack(spacing: 12) {
                formRow("Course code") {
                    TextField("e.g. MATH 101", text: $draft.sourceCourseCode)
                        .textFieldStyle(.roundedBorder)
                }
                formRow("Credits") {
                    TextField("3", text: $draft.sourceCredits)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 72)
                }
            }
            formRow("Course title (optional)") {
                TextField("College Algebra", text: $draft.sourceCourseTitle)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private var targetCourseSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Target course")
            HStack(spacing: 12) {
                formRow("Course code") {
                    TextField("e.g. MATH 1100", text: $draft.targetCourseCode)
                        .textFieldStyle(.roundedBorder)
                }
                formRow("Credits") {
                    TextField("3", text: $draft.targetCredits)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 72)
                }
            }
            formRow("Course title (optional)") {
                TextField("Algebra I", text: $draft.targetCourseTitle)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private var mappingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Mapping")
            formRow("Equivalency type") {
                Picker("Equivalency type", selection: $draft.equivalencyKind) {
                    ForEach(TransferEquivalencyKind.allCases, id: \.self) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 280, alignment: .leading)
            }
        }
    }

    private var optionalSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Optional details")
            formRow("Effective term") {
                TextField("Fall 2024", text: $draft.effectiveTerm)
                    .textFieldStyle(.roundedBorder)
            }
            formRow("Source URL") {
                TextField("https://…", text: $draft.sourceURL)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private var proofUploadSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Results document")
            Text("Upload a PDF of the official transfer evaluation, transcript excerpt, or articulation printout.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button {
                    showProofImporter = true
                } label: {
                    Label(proofPDFFileName == nil ? "Upload PDF" : "Replace PDF", systemImage: "doc.badge.plus")
                }
                .disabled(isSaving)

                if let selectedProofName = proofPDFFileName {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.fill")
                            .foregroundStyle(DesignSystem.Colors.primary)
                        Text(selectedProofName)
                            .font(.callout)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button {
                            proofPDFURL = nil
                            proofPDFFileName = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Remove PDF")
                        .disabled(isSaving)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(DesignSystem.Colors.surface, in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button {
                Task { await saveEntry() }
            } label: {
                if isSaving {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("Save Equivalency")
                }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(isSaving)
        }
        .padding(20)
    }

    @MainActor
    private func saveEntry() async {
        isSaving = true
        defer { isSaving = false }
        if let message = await onSave(draft, proofPDFURL) {
            validationMessage = message
        } else {
            dismiss()
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.headline)
    }

    private func formRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
