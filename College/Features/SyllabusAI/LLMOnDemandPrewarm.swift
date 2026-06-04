// LLMOnDemandPrewarm.swift
// Feature: SyllabusAI
// Purpose: SyllabusAI module — LLMOnDemandPrewarm.
// Data: CollegePersistence / repositories when applicable.

import Foundation

/// Pre-warms the JSON worker when the user opens an on-device LLM surface (assistant, syllabus, etc.).
enum LLMOnDemandPrewarm {
    static func prewarmJsonWorkerIfInstalled() {
        Task.detached(priority: .utility) {
            guard await ModelManager.shared.isModelInstalled(.jsonWorker) else { return }
            guard let modelPath = try? await ModelManager.shared.modelDirectoryURL(for: .jsonWorker) else { return }
            await LocalLLMRunner.shared.preWarm(modelPath: modelPath)
        }
    }
}
