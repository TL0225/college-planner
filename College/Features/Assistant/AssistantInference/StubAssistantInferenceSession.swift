// StubAssistantInferenceSession.swift
// Feature: Assistant
// Purpose: Assistant module — StubAssistantInferenceSession.
// Data: CollegePersistence / repositories when applicable.

import Foundation

struct StubAssistantInferenceSession: AssistantInferenceSession {
    func plan(request: AssistantPlanningRequest) async -> AssistantPlanningResult {
        let message = request.message.trimmingCharacters(in: .whitespacesAndNewlines)

        if request.planningToolContext != nil,
           !(request.planningToolContext?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) {
            let summary = """
            Stub summary: tool results are in your context. Programs show remaining credits; follow your advisor for official rules.
            """
            return AssistantPlanningResult(
                action: .finalAnswer(summary),
                fallbackReply: nil,
                failureReason: nil,
                diagnostics: "stub_after_tools",
                backend: .stub
            )
        }

        if message.localizedCaseInsensitiveContains("UITEST_CONFIRM create task") {
            let call = AssistantToolCallEnvelope(
                tool: "createTask",
                arguments: [
                    "title": .string("UITest Seeded Task"),
                    "dueDateISO8601": .null
                ]
            )
            return AssistantPlanningResult(
                action: .toolCall(call),
                fallbackReply: nil,
                failureReason: nil,
                diagnostics: nil,
                backend: .stub
            )
        }

        if message.localizedCaseInsensitiveContains("UITEST_STUB get program progress") {
            return AssistantPlanningResult(
                action: .toolCall(AssistantToolCallEnvelope(tool: "getProgramProgress", arguments: [:])),
                fallbackReply: nil,
                failureReason: nil,
                diagnostics: nil,
                backend: .stub
            )
        }

        if message.localizedCaseInsensitiveContains("UITEST_STUB decode salvage") {
            return AssistantPlanningResult(
                action: .finalAnswer("Salvaged from fences"),
                fallbackReply: nil,
                failureReason: nil,
                diagnostics: "stub_salvage",
                backend: .stub
            )
        }

        let fallback = "Stub planner: use UITEST_STUB get program progress or UITEST_CONFIRM create task for scripted flows."
        return AssistantPlanningResult(
            action: .finalAnswer(fallback),
            fallbackReply: nil,
            failureReason: nil,
            diagnostics: nil,
            backend: .stub
        )
    }
}
