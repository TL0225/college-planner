// AssistantCancellationTests.swift
import Foundation
import Testing
@testable import College

@Suite("Assistant Cancellation")
struct AssistantCancellationTests {

    @Test("Cancel active generation clears responding")
    @MainActor
    func cancelActiveGenerationClearsResponding() {
        let vm = AIAssistantViewModel()
        vm.startGeneration {
            try? await Task.sleep(for: .seconds(2))
        }
        #expect(vm.isResponding)
        vm.cancelActiveGeneration()
        #expect(!vm.isResponding)
    }

    @Test("Telemetry records cancelled fallback")
    func telemetryRecordsCancelledFallback() {
#if DEBUG
        AssistantTurnTelemetry.resetForTesting()
        defer { AssistantTurnTelemetry.resetForTesting() }
        AssistantTurnTelemetry.record(
            AssistantTurnTelemetryRecord(
                intent: "next_semester_plan",
                path: .llmPreferred,
                latencyMS: 500,
                personalizationEligible: false,
                fallbackKind: "cancelled",
                toolHopCount: 1,
                timestamp: Date()
            )
        )
        #expect(AssistantTurnTelemetry.counter("fallback.cancelled") == 1)
#endif
    }
}
