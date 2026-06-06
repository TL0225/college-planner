// SettingsCatalogReviewDiagnosticsView.swift
// Feature: Settings
// Purpose: Tier 2 catalog review queue, layout drift, and structural diff detail.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI

struct SettingsCatalogReviewDiagnosticsView: View {
    let schoolID: String

    @AppStorage("catalog.entityLLM.enabled") private var entityLLMEnabled = false
    @State private var validationMessage: String?
    @State private var isValidating = false

    private var reviewItems: [CatalogReviewQueue.Item] {
        CatalogReviewQueue.load().filter { $0.schoolID == schoolID || schoolID.isEmpty }
    }

    private var layoutFingerprint: CatalogLayoutFingerprint? {
        schoolID.isEmpty ? nil : CatalogLayoutFingerprintStore.latest(forSchoolID: schoolID)
    }

    private var structuralDiff: CatalogStructuralDiffReport? {
        schoolID.isEmpty ? nil : CatalogStructuralDiffStore.load(schoolID: schoolID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let layoutFingerprint {
                Text("Layout fingerprint — \(layoutFingerprint.layoutProfileID)")
                    .font(.caption.weight(.semibold))
                Text("Recorded \(layoutFingerprint.recordedAt.formatted(date: .abbreviated, time: .shortened)) · sig \(layoutFingerprint.featureSignature.prefix(12))…")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if !schoolID.isEmpty,
                   let corpus = CatalogLayoutCorpus.load(
                       schoolID: schoolID,
                       layoutProfileID: layoutFingerprint.layoutProfileID
                   ) {
                    Text("Layout corpus — \(corpus.engine) · \(corpus.exampleURLs.count) example URL(s)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if let structuralDiff, structuralDiff.hasChanges {
                Text("Structural diff")
                    .font(.caption.weight(.semibold))
                Text("Programs +\(structuralDiff.programsAdded)/-\(structuralDiff.programsRemoved) · Courses +\(structuralDiff.coursesAdded)/-\(structuralDiff.coursesRemoved)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if !structuralDiff.programsRenamed.isEmpty {
                    Text("Program renames (\(structuralDiff.programsRenamed.count))")
                        .font(.caption2.weight(.medium))
                    ForEach(structuralDiff.programsRenamed.prefix(5), id: \.stableID) { rename in
                        Text("\(rename.previousDisplayKey) → \(rename.currentDisplayKey)")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
                if !structuralDiff.coursesRenamed.isEmpty {
                    Text("Course renames (\(structuralDiff.coursesRenamed.count))")
                        .font(.caption2.weight(.medium))
                    ForEach(structuralDiff.coursesRenamed.prefix(5), id: \.stableID) { rename in
                        Text("\(rename.previousDisplayKey) → \(rename.currentDisplayKey)")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Toggle("Entity LLM validation (review tooling)", isOn: $entityLLMEnabled)
                .font(.caption)

            if let validationMessage {
                Text(validationMessage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            reviewQueueSection
        }
    }

    @ViewBuilder
    private var reviewQueueSection: some View {
        let critical = reviewItems.filter { $0.severity == .critical }
        let warning = reviewItems.filter { $0.severity == .warning }
        let info = reviewItems.filter { $0.severity == .informational }

        if reviewItems.isEmpty {
            EmptyView()
        } else {
            Text("Review queue")
                .font(.caption.weight(.semibold))
            severityGroup(title: "Critical", items: critical, color: .red)
            severityGroup(title: "Warning", items: warning, color: .orange)
            severityGroup(title: "Info", items: info, color: .secondary)
        }
    }

    @ViewBuilder
    private func severityGroup(title: String, items: [CatalogReviewQueue.Item], color: Color) -> some View {
        if items.isEmpty {
            EmptyView()
        } else {
            Text("\(title) (\(items.count))")
                .font(.caption2.weight(.medium))
                .foregroundStyle(color)
            ForEach(Array(items.prefix(8).enumerated()), id: \.offset) { _, item in
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.reason)
                        .font(.caption2)
                    if let snapshotID = item.snapshotID,
                       let snapshot = CatalogReviewSnapshotStore.load(id: snapshotID) {
                        if let profile = snapshot.layoutProfileID {
                            Text("Profile \(profile)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        if let excerpt = snapshot.excerpt, !excerpt.isEmpty {
                            Text(excerpt)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        if let metrics = snapshot.metrics {
                            Text("Programs \(metrics.programsFound) · courses \(metrics.coursesFound)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        if let validation = CatalogEntityLLMValidationStore.load(snapshotID: snapshotID) {
                            let status = validation.result.passed ? "passed" : "failed"
                            Text("Auto LLM validation — \(status)")
                                .font(.caption2)
                                .foregroundStyle(validation.result.passed ? Color.secondary : Color.orange)
                            if let suggestion = validation.result.suggestedDisplayKey, !suggestion.isEmpty {
                                Text("Suggestion: \(suggestion)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    if entityLLMEnabled, item.severity != .informational {
                        Button(isValidating ? "Validating…" : "Validate with LLM") {
                            Task { await validateItem(item) }
                        }
                        .font(.caption2)
                        .disabled(isValidating)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func validateItem(_ item: CatalogReviewQueue.Item) async {
        isValidating = true
        defer { isValidating = false }
        let snapshot = item.snapshotID.flatMap { CatalogReviewSnapshotStore.load(id: $0) }
        let request = CatalogEntityLLMValidator.ValidationRequest(
            entityType: .program,
            displayKey: item.reason,
            sourceURL: snapshot?.sourceURL ?? "",
            excerpt: snapshot?.excerpt ?? item.reason,
            layoutProfileID: snapshot?.layoutProfileID ?? "unknown",
            confidence: item.confidence ?? 0.4
        )
        guard let result = await CatalogEntityLLMValidator.validate(request) else {
            validationMessage = "LLM validation skipped (disabled, high confidence, or model unavailable)."
            return
        }
        if result.passed {
            validationMessage = "LLM validation passed."
        } else {
            let suggestion = result.suggestedDisplayKey ?? result.suggestedCorrections.joined(separator: ", ")
            validationMessage = "LLM validation failed. Suggestion: \(suggestion.isEmpty ? "none" : suggestion)"
        }
    }
}
