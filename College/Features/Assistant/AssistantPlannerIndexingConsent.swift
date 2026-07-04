// AssistantPlannerIndexingConsent.swift
// Feature: Assistant
// Purpose: Assistant module — AssistantPlannerIndexingConsentSheet.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI

/// First-run consent before any planner SQLite rows are written.
struct AssistantPlannerIndexingConsentSheet: View {
    @Environment(\.dismiss) private var dismiss
    var onTurnOn: () -> Void
    var onNotNow: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Index your planner on this Mac")
                .font(.title2.weight(.semibold))
            Text(
                """
                To answer questions about your schedule and coursework, College reads your calendar, tasks, and courses and stores a searchable index on your device. This data never leaves your Mac.
                """
            )
            .fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(.secondary)
            HStack {
                Button("Not now") {
                    AssistantPlannerIndexingSettings.disableIndexing()
                    UserDefaults.standard.set(true, forKey: AssistantPlannerIndexingSettings.consentPresentedKey)
                    onNotNow()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Turn on") {
                    AssistantPlannerIndexingSettings.enableIndexing()
                    onTurnOn()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(DesignSystem.Spacing.xxl)
        .frame(minWidth: 420, maxWidth: 480)
    }
}

struct SettingsAIPrivacySection: View {
    @AppStorage(AssistantPlannerIndexingSettings.indexingEnabledKey) private var plannerIndexingEnabled = false
    @AppStorage(AssistantPlannerIndexingSettings.documentsIndexingKey) private var documentsIndexingEnabled = true
    @State private var chunkCount: Int = 0
    @State private var isRebuilding = false
    @State private var isBackfilling = false

    var body: some View {
        Section {
            Toggle(isOn: $plannerIndexingEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Let AI reference your schedule and coursework")
                    Text("Stored locally, never shared")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .onChange(of: plannerIndexingEnabled) { _, enabled in
                if enabled {
                    AssistantPlannerIndexingSettings.enableIndexing()
                    PlannerVectorIndexingLifecycle.scheduleInitialIndexIfNeeded()
                } else {
                    AssistantPlannerIndexingSettings.disableIndexing()
                }
                Task { await refreshCount() }
            }

            LabeledContent("Index status") {
                Text("\(AssistantPlannerIndexingSettings.lastIndexedDescription) · \(chunkCount) items")
                    .foregroundStyle(.secondary)
            }

            LabeledContent("Rebuild planner index") {
                Button(isRebuilding ? "Rebuilding…" : "Rebuild") {
                    guard plannerIndexingEnabled else { return }
                    isRebuilding = true
                    Task { @MainActor in
                        await PlannerVectorIndexer.shared.runFullRebuild(reason: "settings")
                        await refreshCount()
                        isRebuilding = false
                    }
                }
                .disabled(!plannerIndexingEnabled || isRebuilding)
            }

            Toggle(isOn: $documentsIndexingEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Index uploaded documents for search")
                    Text("Text extracted on your Mac after import; never uploaded elsewhere")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(!plannerIndexingEnabled)

            LabeledContent("Index existing documents") {
                Button(isBackfilling ? "Indexing…" : "Start") {
                    isBackfilling = true
                    Task { @MainActor in
                        await PlannerVectorIndexer.shared.indexVaultBackfill()
                        await refreshCount()
                        isBackfilling = false
                    }
                }
                .disabled(!plannerIndexingEnabled || !documentsIndexingEnabled || isBackfilling)
            }
        } header: {
            Label("AI & Privacy", systemImage: "sparkles")
        }
        .task { await refreshCount() }
    }

    @MainActor
    private func refreshCount() async {
        chunkCount = (try? await PlannerVectorStore.shared.chunkCount()) ?? 0
    }
}
