// AssistantPromptBuilderTests.swift
// Layer 0 — required prompt construction tests (Swift Testing).

import Foundation
import Testing
@testable import College

@Suite("Assistant Prompt Builder")
struct AssistantPromptBuilderTests {

    @Test("Action prompt segments include JSON schema rules")
    func actionPromptSegmentsIncludeJSONSchema() {
        let segments = AssistantPlanningPromptBuilder.makeActionPromptSegments(
            message: "What classes do I need next semester?",
            role: .academicAdvisor,
            contextSummary: "Major: UITest Computer Science",
            recentConversation: nil,
            toolCatalogJSON: #"{"tools":["draftSemesterPlan"]}"#,
            planningToolContext: nil,
            attachmentContextBlock: nil
        )
        let assembled = segments.assembled
        #expect(assembled.contains("Return ONLY valid JSON"))
        #expect(assembled.contains("draftSemesterPlan") || assembled.contains("tool"))
        #expect(assembled.contains("UITest Computer Science"))
        #expect(assembled.contains("What classes do I need next semester?"))
    }

    @Test("Financial aid role includes aid-specific instructions")
    func financialAidRoleInstructions() {
        let segments = AssistantPlanningPromptBuilder.makeActionPromptSegments(
            message: "When is FAFSA due?",
            role: .financialAid,
            contextSummary: "Student context",
            recentConversation: nil,
            toolCatalogJSON: "[]",
            planningToolContext: nil,
            attachmentContextBlock: nil
        )
        #expect(segments.assembled.localizedCaseInsensitiveContains("fafsa")
            || segments.assembled.localizedCaseInsensitiveContains("financial"))
    }

    @Test("Phase 8 guidance is stable golden substring")
    func phase8GuidanceGolden() {
        let guidance = AssistantPlanningPromptBuilder.phase8AppAgentGuidance()
        #expect(guidance.contains("Learning Management System"))
        #expect(guidance.contains("searchDocuments"))
        #expect(guidance.contains("confirmation"))
    }

    @Test("Recent conversation block preserved in segments")
    func recentConversationBlockPreserved() {
        let segments = AssistantPlanningPromptBuilder.makeActionPromptSegments(
            message: "Only fall courses",
            role: .academicAdvisor,
            contextSummary: "ctx",
            recentConversation: "User: What classes do I need?\nAssistant: Here is a plan.",
            toolCatalogJSON: "[]",
            planningToolContext: nil,
            attachmentContextBlock: nil
        )
        #expect(segments.conversation.contains("Recent conversation"))
        #expect(segments.conversation.contains("What classes do I need?"))
    }
}
