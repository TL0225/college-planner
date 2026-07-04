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
        case mlxIncompatibleGPU
    }

    #if DEBUG || COLLEGE_TEST_HOOKS
    /// Unit-test override for `SystemLanguageModel.default.isAvailable`.
    nonisolated(unsafe) static var testSystemLanguageModelAvailable: Bool?
    #endif

    /// Whether the assistant chat shell can open (Apple Intelligence and/or on-device JSON worker).
    static func isChatReady() async -> Bool {
        if UITestLaunchFlags.forcesMainUI, UITestLaunchFlags.fakeAssistantModelForUITest {
            return true
        }
        // Avoid probing Apple Intelligence during the same render pass as assistant mount.
        await Task.yield()
        switch await current() {
        case .foundationModels, .jsonWorkerFallback:
            return true
        case .unavailable:
            return false
        }
    }

    static func current() async -> AssistantInferenceAvailability {
        if UITestLaunchFlags.assistantInferenceStubEnabled {
            return .unavailable(reason: .appleIntelligenceUnavailable)
        }

        let foundationModelsAvailable = await MainActor.run { resolvesFoundationModels() }
        if foundationModelsAvailable {
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
            if AppleSiliconPlatform.isMLXCompatible {
                return .jsonWorkerFallback
            }
            if !AppleSiliconPlatform.isSupported {
                return .unavailable(reason: .requiresAppleSilicon)
            }
            return .unavailable(reason: .mlxIncompatibleGPU)
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
        guard AppleSiliconPlatform.isSupported else { return false }
        if #available(macOS 26.0, *) {
            return SystemLanguageModel.default.isAvailable
        }
        return false
    }

    /// Short label for assistant chrome (M30-079 generative-AI identification).
    var displayLabel: String {
        switch self {
        case .foundationModels:
            return "Apple Intelligence"
        case .jsonWorkerFallback:
            return "On-device model"
        case .unavailable:
            return "AI unavailable"
        }
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
        case .mlxIncompatibleGPU:
            return AppleSiliconPlatform.mlxRequirementMessage
        }
    }
}
