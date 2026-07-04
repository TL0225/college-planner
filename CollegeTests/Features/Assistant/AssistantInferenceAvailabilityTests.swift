// AssistantInferenceAvailabilityTests.swift
import Foundation
import Testing
@testable import College

// Shared UserDefaults + static test overrides must not run in parallel.
@Suite("Assistant Inference Availability", .serialized)
struct AssistantInferenceAvailabilityTests {

    private func resetAvailabilityDefaults() {
        AssistantInferenceAvailability.testSystemLanguageModelAvailable = nil
        UserDefaults.standard.removeObject(forKey: AssistantInferenceSettings.preferFoundationModelsKey)
        UserDefaults.standard.removeObject(forKey: AssistantInferenceSettings.localLLMEnabledKey)
    }

    @Test("Foundation models when system language model available")
    func foundationModelsWhenSystemLanguageModelAvailable() async {
        defer { resetAvailabilityDefaults() }
        AssistantInferenceAvailability.testSystemLanguageModelAvailable = true
        UserDefaults.standard.set(true, forKey: AssistantInferenceSettings.localLLMEnabledKey)
        let availability = await AssistantInferenceAvailability.current()
        #expect(availability == .foundationModels)
    }

    @Test("JSON worker fallback when model unavailable but json worker ready")
    func jsonWorkerFallbackWhenModelUnavailableButJsonWorkerReady() async {
        defer { resetAvailabilityDefaults() }
        AssistantInferenceAvailability.testSystemLanguageModelAvailable = false
        UserDefaults.standard.set(true, forKey: AssistantInferenceSettings.localLLMEnabledKey)
        let installed = await ModelManager.shared.isModelInstalled(.jsonWorker)
        guard installed else { return }
        let availability = await AssistantInferenceAvailability.current()
        #expect(availability == .jsonWorkerFallback)
    }

    @Test("Unavailable when neither path ready")
    func unavailableWhenNeitherPathReady() async {
        defer { resetAvailabilityDefaults() }
        AssistantInferenceAvailability.testSystemLanguageModelAvailable = false
        UserDefaults.standard.set(false, forKey: AssistantInferenceSettings.localLLMEnabledKey)
        let availability = await AssistantInferenceAvailability.current()
        guard case .unavailable(let reason) = availability else {
            Issue.record("expected unavailable, got \(availability)")
            return
        }
        #expect(reason == .modelNotInstalled || reason == .localLLMDisabled)
    }

    @Test("Factory uses JSON worker when user disables foundation models")
    @MainActor
    func factoryUsesJsonWorkerWhenUserDisablesFoundationModels() async {
        defer { resetAvailabilityDefaults() }
        AssistantInferenceAvailability.testSystemLanguageModelAvailable = true
        UserDefaults.standard.set(false, forKey: AssistantInferenceSettings.preferFoundationModelsKey)
        let session = AssistantInferenceSessionFactory.makeSession(
            availability: .foundationModels,
            executor: nil
        )
        #expect(session is JsonWorkerAssistantSession)
    }

    @Test("Display labels identify AI provider for chrome")
    func displayLabelsIdentifyProvider() {
        #expect(AssistantInferenceAvailability.foundationModels.displayLabel == "Apple Intelligence")
        #expect(AssistantInferenceAvailability.jsonWorkerFallback.displayLabel == "On-device model")
        #expect(AssistantInferenceAvailability.unavailable(reason: .modelNotInstalled).displayLabel == "AI unavailable")
    }

    @Test("Chat ready when foundation models available without json worker")
    func chatReadyWhenFoundationModelsAvailableWithoutJsonWorker() async {
        defer { resetAvailabilityDefaults() }
        AssistantInferenceAvailability.testSystemLanguageModelAvailable = true
        UserDefaults.standard.set(false, forKey: AssistantInferenceSettings.localLLMEnabledKey)
        let ready = await AssistantInferenceAvailability.isChatReady()
        #expect(ready)
    }
}
