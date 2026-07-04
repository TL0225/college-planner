// CareerApplyCompletionSheet.swift
// Feature: Career / Apply
// Purpose: Confirm user submitted on ATS site; closes apply window.

import SwiftUI

struct CareerApplyCompletionSheet: View {
    let companyName: String
    let resumeFileName: String
    @Binding var appliedAt: Date
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Confirm application submitted")
                .font(.title2.weight(.semibold))
            Text("Did you submit your application on \(companyName)? College will mark this role Applied and record \(resumeFileName).")
                .foregroundStyle(.secondary)
            DatePicker("Applied date", selection: $appliedAt, displayedComponents: .date)
            HStack {
                Button("Not yet", action: onCancel)
                Spacer()
                Button("Yes, I submitted", action: onConfirm)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}
