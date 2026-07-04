// ResumeTailoringSheet.swift
// Feature: Career
// Purpose: Two-column macOS sheet for reviewing AI resume tailoring suggestions.

import SwiftUI
import CollegeCareer

struct ResumeTailoringSheet: View {
    @Bindable var session: CareerResumeEditSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow
    @Environment(AppContainer.self) private var appContainer
    @State private var isSaving = false
    @State private var isOpeningBuilder = false
    @State private var editingSuggestionID: UUID?
    @State private var editDraft = ""

    var body: some View {
        VStack(spacing: 0) {
            tailoringHeader
            Divider()
            HStack(alignment: .top, spacing: 0) {
                suggestionsColumn
                    .frame(minWidth: 340, maxWidth: 400)
                Divider()
                ResumePreviewPane(session: session)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            tailoringFooter
        }
        .frame(minWidth: 720, idealWidth: 780, minHeight: 540, idealHeight: 640)
    }

    private var tailoringHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Tailor for \(session.companyName) · \(session.jobTitle)")
                    .font(.headline)
                Text(session.platform.rawValue.capitalized)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.12), in: Capsule())
            }
            Spacer()
            HStack(spacing: 8) {
                Text("Match")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(session.liveMatchScoreBefore)%")
                    .font(.caption.monospacedDigit().weight(.semibold))
                Image(systemName: "arrow.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("\(session.liveMatchScoreAfter)%")
                    .font(.caption.monospacedDigit().weight(.bold))
                    .foregroundStyle(.green)
                if session.liveMatchScoreAfter > session.liveMatchScoreBefore {
                    Text("(+\(session.liveMatchScoreAfter - session.liveMatchScoreBefore))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.green)
                }
            }
            if session.isGenerating {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var suggestionsColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Suggestions (\(session.suggestions.count))")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                if session.suggestions.isEmpty, !session.isGenerating {
                    Text("No suggestions yet. Try re-running after the job description finishes loading.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                }

                ForEach(session.suggestions) { suggestion in
                    SuggestionCardView(
                        suggestion: suggestion,
                        decision: session.decisions[suggestion.id],
                        isEditing: editingSuggestionID == suggestion.id,
                        editDraft: $editDraft,
                        onAccept: { accept(suggestion) },
                        onReject: { reject(suggestion) },
                        onStartEdit: { startEdit(suggestion) },
                        onApplyEdit: { applyEdit(suggestion) },
                        onUndo: { session.undo(decisionFor: suggestion.id) }
                    )
                    .padding(.horizontal, 12)
                }
            }
            .padding(.bottom, 16)
        }
        .background(Color.secondary.opacity(0.04))
    }

    private var tailoringFooter: some View {
        HStack {
            Button("Apply All Safe Edits") {
                session.applyAllSafe()
            }
            .disabled(session.isGenerating || session.suggestions.isEmpty)

            Spacer()

            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)

            Button {
                Task { @MainActor in await openInBuilder() }
            } label: {
                if isOpeningBuilder {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Open in Builder")
                }
            }
            .disabled(isOpeningBuilder || isSaving || session.isGenerating)

            Button {
                Task { @MainActor in await saveTailoredCopy() }
            } label: {
                if isSaving {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Save Tailored Copy")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSaving || session.isGenerating)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private func accept(_ suggestion: CareerResumeSuggestion) {
        session.decisions[suggestion.id] = .accepted
        session.refreshLiveScore()
    }

    private func reject(_ suggestion: CareerResumeSuggestion) {
        session.decisions[suggestion.id] = .rejected
        session.refreshLiveScore()
    }

    private func startEdit(_ suggestion: CareerResumeSuggestion) {
        editingSuggestionID = suggestion.id
        editDraft = suggestion.proposedBullet.isEmpty ? suggestion.originalBullet : suggestion.proposedBullet
    }

    private func applyEdit(_ suggestion: CareerResumeSuggestion) {
        let trimmed = editDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        session.decisions[suggestion.id] = .edited(trimmed)
        editingSuggestionID = nil
        session.refreshLiveScore()
    }

    private func saveTailoredCopy() async {
        isSaving = true
        defer { isSaving = false }
        do {
            if let exported = try await session.saveTailoredCopy(using: appContainer.persistence) {
                appContainer.appNotifications.post(
                    kind: .success,
                    title: "Tailored resume saved",
                    message: exported.customDisplayName ?? exported.fileName
                )
                dismiss()
            }
        } catch {
            appContainer.appNotifications.post(
                kind: .error,
                title: "Save failed",
                message: error.localizedDescription
            )
        }
    }

    private func openInBuilder() async {
        isOpeningBuilder = true
        defer { isOpeningBuilder = false }
        do {
            guard let document = try await session.createBuilderDraft(using: appContainer.persistence) else { return }
            ResumeNavigationPort.openResumeBuilder(openWindow: openWindow, documentID: document.id)
            dismiss()
        } catch {
            appContainer.appNotifications.post(
                kind: .error,
                title: "Could not open builder",
                message: error.localizedDescription
            )
        }
    }
}

private struct SuggestionCardView: View {
    let suggestion: CareerResumeSuggestion
    let decision: CareerResumeEditSession.SuggestionDecision?
    let isEditing: Bool
    @Binding var editDraft: String
    var onAccept: () -> Void
    var onReject: () -> Void
    var onStartEdit: () -> Void
    var onApplyEdit: () -> Void
    var onUndo: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(suggestion.entryHeading)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if let decision {
                    decisionBadge(decision)
                }
            }

            if case .accepted = decision {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(suggestion.proposedBullet.isEmpty ? suggestion.originalBullet : suggestion.proposedBullet)
                        .font(.caption)
                        .lineLimit(3)
                    Spacer()
                    Button("Undo", action: onUndo)
                        .font(.caption2)
                }
            } else if case .rejected = decision {
                HStack {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                    Text(suggestion.originalBullet)
                        .font(.caption)
                        .strikethrough()
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Spacer()
                    Button("Undo", action: onUndo)
                        .font(.caption2)
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Before")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(suggestion.originalBullet)
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)

                    if suggestion.type != .metricPrompt || !suggestion.proposedBullet.isEmpty {
                        Text("After")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        if isEditing {
                            TextEditor(text: $editDraft)
                                .font(.caption)
                                .frame(minHeight: 60)
                            Button("Apply edit", action: onApplyEdit)
                                .font(.caption)
                        } else {
                            wordDiffView
                        }
                    }

                    Text(suggestion.rationale)
                        .font(.caption2)
                        .italic()
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        if suggestion.type != .metricPrompt, !suggestion.proposedBullet.isEmpty {
                            Button("Accept", action: onAccept)
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                        }
                        Button("Reject", action: onReject)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        if suggestion.type != .metricPrompt {
                            Button("Edit myself", action: onStartEdit)
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                    }
                }
            }
        }
        .padding(DesignSystem.Spacing.md)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder
    private var wordDiffView: some View {
        let segments = CareerResumeWordDiff.diff(
            original: suggestion.originalBullet,
            revised: suggestion.proposedBullet
        )
        Text(attributedDiff(segments))
            .font(.caption)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func attributedDiff(_ segments: [CareerResumeWordDiff.Segment]) -> AttributedString {
        var result = AttributedString()
        for segment in segments {
            var part = AttributedString(segment.text + " ")
            switch segment.kind {
            case .unchanged:
                break
            case .removed:
                part.strikethroughStyle = .single
                part.foregroundColor = .red
            case .added:
                part.foregroundColor = .green
            }
            result.append(part)
        }
        return result
    }

    @ViewBuilder
    private func decisionBadge(_ decision: CareerResumeEditSession.SuggestionDecision) -> some View {
        switch decision {
        case .accepted, .edited:
            Text("Accepted")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.green)
        case .rejected:
            Text("Rejected")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.red)
        }
    }
}

struct ResumePreviewPane: View {
    let session: CareerResumeEditSession

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Resume preview")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                Text(session.previewText())
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(DesignSystem.Spacing.lg)
            }
        }
    }
}
