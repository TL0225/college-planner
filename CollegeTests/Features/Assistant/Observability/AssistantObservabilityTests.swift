// AssistantObservabilityTests.swift
// Layer 9 — telemetry, traces, redaction (Swift Testing).

import Foundation
import Testing
@testable import College

@Suite("Assistant Observability")
struct AssistantObservabilityTests {

    @Test("Turn telemetry records intent and path")
    func turnTelemetryRecordsIntentAndPath() {
#if DEBUG
        AssistantTurnTelemetry.resetForTesting()
        defer { AssistantTurnTelemetry.resetForTesting() }
        AssistantTurnTelemetry.record(
            AssistantTurnTelemetryRecord(
                intent: "degree_policy_lookup",
                path: .toolLoop,
                latencyMS: 220,
                personalizationEligible: true,
                fallbackKind: nil,
                toolHopCount: 2,
                timestamp: Date()
            )
        )
        #expect(AssistantTurnTelemetry.counter("path.toolLoop") == 1)
        #expect(AssistantTurnTelemetry.counter("intent.degree_policy_lookup") == 1)
        let recent = AssistantTurnTelemetry.recentRecords(limit: 1)
        #expect(recent.first?.toolHopCount == 2)
#endif
    }

    @Test("Log redactor masks email-like tokens")
    func logRedactorMasksEmail() {
        let input = "Contact student at alice@university.edu for details"
        let redacted = AssistantLogRedactor.redactForLog(input)
        #expect(!redacted.contains("alice@university.edu"))
    }

    @Test("Eval recorder captures latency and route path")
    @MainActor
    func evalRecorderCapturesLatency() async {
        let record = await AssistantEvalRecorder.evaluatePrompt("What's my major?")
        #expect(record.routePath == "deterministic" || !record.reply.isEmpty)
        #expect(record.latencyMS != nil)
    }
}
