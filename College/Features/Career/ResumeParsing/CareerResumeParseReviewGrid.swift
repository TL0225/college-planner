// CareerResumeParseReviewGrid.swift
// Feature: Career / ResumeParsing
// Purpose: Required post-parse review UI before Profile import or apply.

import SwiftUI

struct CareerResumeParseReviewGrid: View {
    let document: ParsedResumeDocument
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section("Format: \(document.format.rawValue)") {
                    if let name = document.personalName { LabeledContent("Name", value: name) }
                    if let email = document.email { LabeledContent("Email", value: email) }
                }
                Section("Experience (\(document.experiences.count))") {
                    ForEach(document.experiences) { row in
                        VStack(alignment: .leading) {
                            Text(row.title).font(.headline)
                            Text(row.company).font(.subheadline)
                            if let type = row.employmentType {
                                Text(type.rawValue).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section("Education (\(document.education.count))") {
                    ForEach(document.education) { row in
                        Text(row.institution ?? "School")
                    }
                }
            }
            .navigationTitle("Review parsed resume")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: onCancel) }
                ToolbarItem(placement: .confirmationAction) { Button("Confirm", action: onConfirm) }
            }
        }
        .frame(minWidth: 520, minHeight: 420)
    }
}
