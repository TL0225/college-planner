// AssistantInferenceSessionTests.swift
// Feature: Assistant
// Purpose: Assistant module — AssistantInferenceSessionTests.
// Data: CollegePersistence / repositories when applicable.

import XCTest
@testable import College

final class AssistantInferenceSessionTests: XCTestCase {

    override func tearDown() {
        AssistantInferenceAvailability.testSystemLanguageModelAvailable = nil
        super.tearDown()
    }

    func testStubSessionReturnsToolCall() async {
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
            return XCTFail("expected tool call")
        }
        XCTAssertEqual(envelope.tool, "getProgramProgress")
        XCTAssertEqual(result.backend, .stub)
    }

    func testPlanResponseDelegatesToStubBackend() async {
        let previous = ProcessInfo.processInfo.environment["COLLEGE_ASSISTANT_INFERENCE_BACKEND"]
        setenv("COLLEGE_ASSISTANT_INFERENCE_BACKEND", "stub", 1)
        defer {
            if let previous {
                setenv("COLLEGE_ASSISTANT_INFERENCE_BACKEND", previous, 1)
            } else {
                unsetenv("COLLEGE_ASSISTANT_INFERENCE_BACKEND")
            }
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
            return XCTFail("expected tool call from stub session")
        }
        XCTAssertEqual(envelope.tool, "getProgramProgress")
    }

    func testStubHopFinalAnswerAfterToolContext() async {
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
            return XCTFail("expected final answer")
        }
        XCTAssertTrue(text.contains("Stub summary"))
    }
}
