// ResumeAttachmentSheet.swift
// Feature: Career / Resumes
// Purpose: Choose which resume to attach before Apply in College.

import SwiftUI
import CollegeCareer

struct ResumeAttachmentSheet: View {
    let rows: [CareerResumeMatchRow]
    let jobTitle: String
    let companyName: String
    var onUseForApply: (CareerResumeMatchRow) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedResumeID: UUID?

    init(
        rows: [CareerResumeMatchRow],
        jobTitle: String,
        companyName: String,
        onUseForApply: @escaping (CareerResumeMatchRow) -> Void
    ) {
        self.rows = rows
        self.jobTitle = jobTitle
        self.companyName = companyName
        self.onUseForApply = onUseForApply
        let recommended = rows.first(where: \.isRecommended) ?? rows.first
        _selectedResumeID = State(initialValue: recommended?.resumeDocumentID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            resumeList
            footer
        }
        .padding(DesignSystem.Spacing.xl)
        .frame(minWidth: 440, minHeight: 360)
        .accessibilityIdentifier("career.resumeAttachment.sheet")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Choose resume")
                .font(.title2.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Text("\(companyName) · \(jobTitle)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Select which resume to attach when applying in College.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Choose resume for \(companyName), \(jobTitle)")
    }

    @ViewBuilder
    private var resumeList: some View {
        if rows.isEmpty {
            Text("Upload and parse a resume in Career → Resumes to apply in College.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        } else {
            List(rows, selection: $selectedResumeID) { row in
                resumeRow(row)
                    .tag(row.resumeDocumentID)
            }
            .listStyle(.inset)
        }
    }

    private func resumeRow(_ row: CareerResumeMatchRow) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(row.displayName)
                        .font(.body.weight(.medium))
                    if row.isRecommended {
                        Text("Recommended")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.12), in: Capsule())
                    }
                }
                if row.overallScore > 0 {
                    Text("\(row.overallScore)% match")
                        .font(.caption)
                        .foregroundStyle(CareerResumeLibraryTheme.jobMatchTierColor(for: row.overallScore))
                } else {
                    Text("Match score unavailable")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if selectedResumeID == row.resumeDocumentID {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.accentColor)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            selectedResumeID = row.resumeDocumentID
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Cancel") { dismiss() }
                .accessibilityLabel("Cancel resume selection")
            Button("Use for apply") { confirmSelection() }
                .buttonStyle(.borderedProminent)
                .disabled(selectedRow == nil)
                .accessibilityIdentifier("career.resumeAttachment.useForApply")
                .accessibilityLabel("Use selected resume for apply")
                .accessibilityHint(selectedRow == nil ? "Select a resume first" : "Opens Apply in College")
        }
    }

    private var selectedRow: CareerResumeMatchRow? {
        guard let selectedResumeID else { return nil }
        return rows.first { $0.resumeDocumentID == selectedResumeID }
    }

    private func confirmSelection() {
        guard let row = selectedRow else { return }
        dismiss()
        onUseForApply(row)
    }
}
