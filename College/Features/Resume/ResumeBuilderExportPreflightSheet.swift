// ResumeBuilderExportPreflightSheet.swift
// Feature: Resume
// Purpose: Export/save preflight — parse review grid + readiness gates.

import SwiftUI

enum ResumeBuilderExportAction: Sendable {
    case exportPDF
    case saveToLibrary
}

struct ResumeBuilderExportPreflightSheet: View {
    let profile: CareerResumeStructuredProfile
    let parserHealthPercent: Int?
    let requiresManualTypstConfirm: Bool
    let action: ResumeBuilderExportAction
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @State private var confirmedManualTypst = false

    private var blocksExport: Bool {
        ResumeExportReadiness.blocksExport(parserHealthPercent: parserHealthPercent)
    }

    private var canConfirm: Bool {
        if blocksExport { return false }
        if requiresManualTypstConfirm && !confirmedManualTypst { return false }
        return true
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                if blocksExport {
                    Label(
                        "Parser health is below \(ResumeExportReadiness.minimumParserHealthPercent)% — review fields before exporting.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.callout)
                    .foregroundStyle(.orange)
                }

                if requiresManualTypstConfirm {
                    Toggle("I reviewed my manual Typst source", isOn: $confirmedManualTypst)
                        .font(.callout)
                }

                Text("Review exported fields")
                    .font(.headline)

                ResumeParsedProfileTabbedView(profile: profile)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(20)
            .navigationTitle(action == .exportPDF ? "Export PDF" : "Save to Library")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(actionTitle, action: onConfirm)
                        .disabled(!canConfirm)
                }
            }
        }
        .frame(minWidth: 560, minHeight: 520)
    }

    private var actionTitle: String {
        switch action {
        case .exportPDF: return "Export"
        case .saveToLibrary: return "Save"
        }
    }
}
