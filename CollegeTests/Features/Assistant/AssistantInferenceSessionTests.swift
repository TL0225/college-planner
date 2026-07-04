// AssistantInferenceSessionTests.swift
// Inference session stub behavior (Swift Testing).

import Foundation
import Testing
@testable import College

// Mutates process environment and static inference overrides.
@Suite("Assistant Inference Session", .serialized)
struct AssistantInferenceSessionTests {

    @Test("Stub session returns tool call")
    func stubSessionReturnsToolCall() async {
        let request = AssistantPlanningRequest(
            message: "UITEST_STUB get program progress",
            role: .academicAdvisor,
            contextSummary: "Planner context",
            recentConversation: nil,
            persona: .academicAdvisor,
            allowedToolNames: ["getProgramProgress"],
            planningToolContext: nil,
            attachmentContextBlock: nil,
            policyContext: nil,
            toolDescriptors: [],
            toolCatalogJSON: "[]"
        )

        let result = await StubAssistantInferenceSession().plan(request: request)
        guard case .toolCall(let envelope)? = result.action else {
            Issue.record("expected tool call")
            return
        }
        #expect(envelope.tool == "getProgramProgress")
        #expect(result.backend == .stub)
    }

    @Test("Plan response delegates to stub backend")
    @MainActor
    func planResponseDelegatesToStubBackend() async {
        let previous = ProcessInfo.processInfo.environment["COLLEGE_ASSISTANT_INFERENCE_BACKEND"]
        setenv("COLLEGE_ASSISTANT_INFERENCE_BACKEND", "stub", 1)
        defer {
            if let previous {
                setenv("COLLEGE_ASSISTANT_INFERENCE_BACKEND", previous, 1)
            } else {
                unsetenv("COLLEGE_ASSISTANT_INFERENCE_BACKEND")
            }
            AssistantInferenceAvailability.testSystemLanguageModelAvailable = nil
        }

        let outcome = await AIAssistantService.shared.planResponse(
            message: "UITEST_STUB get program progress",
            role: .academicAdvisor,
            contextSummary: "Planner context",
            recentConversation: nil,
            toolCatalogJSON: "[]",
            allowedPlanningToolNames: ["getProgramProgress"]
        )

        guard case .toolCall(let envelope)? = outcome.action else {
            Issue.record("expected tool call from stub session")
            return
        }
        #expect(envelope.tool == "getProgramProgress")
    }

    @Test("Stub hop final answer after tool context")
    func stubHopFinalAnswerAfterToolContext() async {
        let request = AssistantPlanningRequest(
            message: "summarize",
            role: .academicAdvisor,
            contextSummary: "ctx",
            recentConversation: nil,
            persona: .academicAdvisor,
            allowedToolNames: [],
            planningToolContext: "tool output",
            attachmentContextBlock: nil,
            policyContext: nil,
            toolDescriptors: [],
            toolCatalogJSON: "[]"
        )
        let result = await StubAssistantInferenceSession().plan(request: request)
        guard case .finalAnswer(let text)? = result.action else {
            Issue.record("expected final answer")
            return
        }
        #expect(text.contains("Stub summary"))
    }
}
