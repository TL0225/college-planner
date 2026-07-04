// ResumeRequiredEmptyState.swift
// Feature: Career / Resumes
// Purpose: Full empty-state CTA for the resume library.

import SwiftUI

struct ResumeRequiredEmptyState: View {
    let onUpload: () -> Void
    let onBuild: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(ResumeRequiredCopy.emptyTitle, systemImage: "doc.richtext")
        } description: {
            Text(ResumeRequiredCopy.emptyDescription)
        } actions: {
            Button(ResumeRequiredCopy.uploadButton, action: onUpload)
                .buttonStyle(.borderedProminent)
            Button(ResumeRequiredCopy.buildButton, action: onBuild)
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(DesignSystem.Spacing.xl)
    }
}
