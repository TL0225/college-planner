// PlannerVectorIndexingLifecycle.swift
// Feature: Assistant
// Purpose: Assistant module — PlannerVectorIndexingLifecycle.
// Data: CollegePersistence / repositories when applicable.

import Foundation

/// Registers planner vector indexing (local store-only, Phase 7f).
enum PlannerVectorIndexingLifecycle {
    nonisolated(unsafe) private static var started = false

    @MainActor
    static func start() {
        guard !started else { return }
        started = true
        AssistantPlannerIndexingSettings.applyUITestOverridesIfNeeded()
        scheduleInitialIndexIfNeeded()
    }

    static func invalidateAllVectorState(reason: String) async {
        try? await PlannerVectorStore.shared.deleteAllRows()
        AssistantPlannerIndexingSettings.clearIndexedState()
        await MainActor.run {
            DebugLogger.shared.log(
                "Planner vector state invalidated: \(reason)",
                category: .system,
                level: .info
            )
        }
    }

    static func scheduleInitialIndexIfNeeded() {
        guard AssistantPlannerIndexingSettings.isIndexingEnabled else { return }
        Task(priority: .utility) {
            try? await Task.sleep(nanoseconds: 800_000_000)
            if Task.isCancelled { return }
            let count = (try? await PlannerVectorStore.shared.chunkCount()) ?? 0
            if count == 0 {
                await PlannerVectorIndexer.shared.runFullRebuild(reason: "initial")
            }
        }
    }
}
