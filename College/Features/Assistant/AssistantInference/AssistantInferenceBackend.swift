// AssistantInferenceBackend.swift
// Feature: Assistant
// Purpose: Assistant module — AssistantInferenceBackend.
// Data: CollegePersistence / repositories when applicable.

import Foundation

enum AssistantInferenceBackend: String, Sendable {
    case foundationModels
    case jsonWorker
    case stub
}
