// ResumeRequiredBanner.swift
// Feature: Career / Resumes
// Purpose: Inline resume-required messaging for job match and similar surfaces.

import SwiftUI
import CollegeCareer

struct ResumeRequiredBanner: View {
    let state: JobBoardDetailMatchState
    var isLoading: Bool = false

    var body: some View {
        Group {
            switch state {
            case .noResume:
                Text(ResumeRequiredCopy.matchPanelNoResume)
            case .awaitingResumeParse:
                labeledProgress(ResumeRequiredCopy.awaitingParse)
            case .awaitingDescription:
                if isLoading {
                    labeledProgress(ResumeRequiredCopy.awaitingDescriptionLoading)
                } else {
                    Text(ResumeRequiredCopy.awaitingDescription)
                }
            case .scoring:
                Text(ResumeRequiredCopy.scoring)
            case .scored:
                EmptyView()
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func labeledProgress(_ message: String) -> some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(message)
        }
    }
}
