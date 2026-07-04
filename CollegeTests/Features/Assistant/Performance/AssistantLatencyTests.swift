// AssistantLatencyTests.swift
// Layer 8 — latency budgets (Swift Testing + ContinuousClock).

import Foundation
import Testing
@testable import College

@Suite("Assistant Latency")
struct AssistantLatencyTests {

    @Test("Simple major lookup under 800ms")
    @MainActor
    func simpleMajorLookupUnder800ms() {
        let clock = ContinuousClock()
        let start = clock.now
        _ = AIAssistantToolRouter.reply(
            for: "what's my major",
            role: .academicAdvisor,
            snapshot: AssistantTestFixtures.csSnapshot,
            activePage: .academics
        )
        #expect(clock.now - start <= .milliseconds(800))
    }

    @Test("Intent classification under 50ms")
    func intentClassificationUnder50ms() {
        let clock = ContinuousClock()
        let start = clock.now
        _ = AssistantIntentSemantics.intentFrame(
            message: "What classes do I need next semester?",
            role: .academicAdvisor
        )
        #expect(clock.now - start <= .milliseconds(50))
    }

    @Test("Telemetry counter increments on record")
    func telemetryCounterIncrements() {
#if DEBUG
        AssistantTurnTelemetry.resetForTesting()
        defer { AssistantTurnTelemetry.resetForTesting() }
        AssistantTurnTelemetry.record(
            AssistantTurnTelemetryRecord(
                intent: "next_semester_plan",
                path: .deterministic,
                latencyMS: 42,
                personalizationEligible: false,
                fallbackKind: nil,
                toolHopCount: 0,
                timestamp: Date()
            )
        )
        #expect(AssistantTurnTelemetry.counter("path.deterministic") >= 1)
#endif
    }
}
