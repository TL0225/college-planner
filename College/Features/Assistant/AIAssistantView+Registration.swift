// AIAssistantView+Registration.swift
// Feature: Assistant
// Purpose: Preload registration + tool dedupe helper (Phase 6 decomposition).

import Foundation

struct AssistantToolCallDedupeRecord {
    var lastOk: Bool
    var consumedFailedRetry: Bool
}

enum AIAssistantFeaturePreloadRegistration {
    @MainActor
    static func register() {
        LaunchPreloadCoordinator.registerFeaturePreload(
            .init(
                id: "assistant",
                title: "Assistant model readiness",
                criticality: .bestEffort,
                timeoutSeconds: 2.4,
                retryLimit: 0,
                run: { _, onProgress, onDetail in
                    onDetail("Checking JSON worker model")
                    if await ModelManager.shared.isModelInstalled(.jsonWorker) {
                        onProgress(1)
                        return
                    }

                    // Never block launch on multi-GB model downloads. Startup only verifies
                    // readiness here; background bootstrap continues after main content appears.
                    onDetail("JSON model not installed yet; download continues after launch")
                    onProgress(1)
                }
            )
        )
    }
}