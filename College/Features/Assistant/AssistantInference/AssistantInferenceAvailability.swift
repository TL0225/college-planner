// AssistantInferenceAvailability.swift
// Feature: Assistant
// Purpose: Assistant module — AssistantInferenceAvailability.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import FoundationModels

enum AssistantInferenceAvailability: Sendable, Equatable {
    case foundationModels
    case jsonWorkerFallback
    case unavailable(reason: UnavailableReason)

    enum UnavailableReason: String, Sendable {
        case appleIntelligenceUnavailable
        case modelNotInstalled
        case localLLMDisabled
        case requiresAppleSilicon
    }

    #if DEBUG || COLLEGE_TEST_HOOKS
    /// Unit-test override for `SystemLanguageModel.default.isAvailable`.
    nonisolated(unsafe) static var testSystemLanguageModelAvailable: Bool?
    #endif

    static func current() async -> AssistantInferenceAvailability {
        if UITestLaunchFlags.assistantInferenceStubEnabled {
            return .unavailable(reason: .appleIntelligenceUnavailable)
        }

        if resolvesFoundationModels() {
            return .foundationModels
        }

        let jsonWorkerInstalled = await ModelManager.shared.isModelInstalled(.jsonWorker)
        let hasExplicitLocalLLMPref = UserDefaults.standard.object(forKey: AssistantInferenceSettings.localLLMEnabledKey) != nil
        var localEnabled = AssistantInferenceSettings.isLocalLLMEnabled
        if !hasExplicitLocalLLMPref, !localEnabled, jsonWorkerInstalled {
            UserDefaults.standard.set(true, forKey: AssistantInferenceSettings.localLLMEnabledKey)
            localEnabled = true
        }

        if jsonWorkerInstalled, localEnabled {
            if AppleSiliconPlatform.isSupported {
                return .jsonWorkerFallback
            }
            return .unavailable(reason: .requiresAppleSilicon)
        }
        if !jsonWorkerInstalled {
            return .unavailable(reason: .modelNotInstalled)
        }
        if !localEnabled {
            return .unavailable(reason: .localLLMDisabled)
        }
        return .unavailable(reason: .appleIntelligenceUnavailable)
    }

    static func resolvesFoundationModels() -> Bool {
        #if DEBUG || COLLEGE_TEST_HOOKS
        if let testSystemLanguageModelAvailable {
            return testSystemLanguageModelAvailable
        }
        #endif
        if #available(macOS 26.0, *) {
            return SystemLanguageModel.default.isAvailable
        }
        return false
    }

    var jsonWorkerFallbackBanner: String? {
        guard case .jsonWorkerFallback = self else { return nil }
        return "Using on-device Qwen (Apple Intelligence unavailable)."
    }

    func unavailableGuidance() -> String? {
        guard case .unavailable(let reason) = self else { return nil }
        switch reason {
        case .appleIntelligenceUnavailable:
            return "Turn on Apple Intelligence in System Settings, or install the on-device JSON model in College Settings → AI & Storage and enable the on-device assistant."
        case .modelNotInstalled:
            return "Install the on-device JSON model in College Settings → AI & Storage, or turn on Apple Intelligence in System Settings."
        case .localLLMDisabled:
            return "Enable the on-device assistant in College Settings → AI & Storage, or turn on Apple Intelligence in System Settings."
        case .requiresAppleSilicon:
            return AppleSiliconPlatform.requirementMessage
        }
    }
}
