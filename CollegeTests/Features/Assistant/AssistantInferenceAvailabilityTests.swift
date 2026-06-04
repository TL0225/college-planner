// AssistantInferenceAvailabilityTests.swift
// Feature: Assistant
// Purpose: Assistant module — AssistantInferenceAvailabilityTests.
// Data: CollegePersistence / repositories when applicable.

import XCTest
@testable import College

final class AssistantInferenceAvailabilityTests: XCTestCase {

    override func tearDown() {
        AssistantInferenceAvailability.testSystemLanguageModelAvailable = nil
        UserDefaults.standard.removeObject(forKey: AssistantInferenceSettings.preferFoundationModelsKey)
        UserDefaults.standard.removeObject(forKey: AssistantInferenceSettings.localLLMEnabledKey)
        super.tearDown()
    }

    func testFoundationModelsWhenSystemLanguageModelAvailable() async {
        AssistantInferenceAvailability.testSystemLanguageModelAvailable = true
        UserDefaults.standard.set(true, forKey: AssistantInferenceSettings.localLLMEnabledKey)

        let availability = await AssistantInferenceAvailability.current()
        XCTAssertEqual(availability, .foundationModels)
    }

    func testJsonWorkerFallbackWhenModelUnavailableButJsonWorkerReady() async throws {
        AssistantInferenceAvailability.testSystemLanguageModelAvailable = false
        UserDefaults.standard.set(true, forKey: AssistantInferenceSettings.localLLMEnabledKey)

        let installed = await ModelManager.shared.isModelInstalled(.jsonWorker)
        guard installed else {
            throw XCTSkip("Qwen JSON worker is not installed on this machine")
        }

        let availability = await AssistantInferenceAvailability.current()
        XCTAssertEqual(availability, .jsonWorkerFallback)
    }

    func testUnavailableWhenNeitherPathReady() async {
        AssistantInferenceAvailability.testSystemLanguageModelAvailable = false
        UserDefaults.standard.set(false, forKey: AssistantInferenceSettings.localLLMEnabledKey)

        let availability = await AssistantInferenceAvailability.current()
        guard case .unavailable(let reason) = availability else {
            return XCTFail("expected unavailable, got \(availability)")
        }
        XCTAssertTrue(reason == .modelNotInstalled || reason == .localLLMDisabled)
    }

    func testFactoryUsesJsonWorkerWhenUserDisablesFoundationModels() async {
        AssistantInferenceAvailability.testSystemLanguageModelAvailable = true
        UserDefaults.standard.set(false, forKey: AssistantInferenceSettings.preferFoundationModelsKey)

        let session = await MainActor.run {
            AssistantInferenceSessionFactory.makeSession(
                availability: .foundationModels,
                executor: nil
            )
        }
        XCTAssertTrue(session is JsonWorkerAssistantSession)
    }
}
