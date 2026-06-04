// AssistantInferenceSettings.swift
// Feature: Assistant
// Purpose: Assistant module — AssistantInferenceSettings.
// Data: CollegePersistence / repositories when applicable.

import Foundation

enum AssistantInferenceSettings {
    static let preferFoundationModelsKey = "assistant.inference.preferFoundationModels"
    static let localLLMEnabledKey = "assistant.localLLM.enabled"

    static var preferFoundationModels: Bool {
        UserDefaults.standard.object(forKey: preferFoundationModelsKey) != nil
            ? UserDefaults.standard.bool(forKey: preferFoundationModelsKey)
            : true
    }

    static var isLocalLLMEnabled: Bool {
        UserDefaults.standard.object(forKey: localLLMEnabledKey) != nil
            ? UserDefaults.standard.bool(forKey: localLLMEnabledKey)
            : false
    }
}
