// AssistantHeadlessTurnRunner.swift
// Layer 5 — headless turn execution without UI (stub LLM path).

import Foundation

enum AssistantHeadlessTurnRunner {

    /// Runs a single prompt through stub planning when available; falls back to router reply.
    static func previewReply(for prompt: String, recentConversation: String? = nil) async -> String? {
        setenv("COLLEGE_ASSISTANT_INFERENCE_BACKEND", "stub", 1)
        let contextBlock = recentConversation ?? "Headless harness"
        let (toolNames, descriptors, catalogJSON) = await MainActor.run {
            (
                AIAssistantToolRegistry.planningToolNames(for: .academicAdvisor),
                AIAssistantToolRegistry.descriptors(for: .academicAdvisor),
                AIAssistantToolRegistry.planningCatalogJSON(for: .academicAdvisor)
            )
        }
        let request = AssistantPlanningRequest(
            message: prompt,
            role: .academicAdvisor,
            contextSummary: contextBlock,
            recentConversation: recentConversation,
            persona: .academicAdvisor,
            allowedToolNames: toolNames,
            planningToolContext: nil,
            attachmentContextBlock: nil,
            policyContext: nil,
            toolDescriptors: descriptors,
            toolCatalogJSON: catalogJSON
        )
        let result = await StubAssistantInferenceSession().plan(request: request)
        switch result.action {
        case .finalAnswer(let text):
            return text
        case .toolCall(let envelope):
            return "[Headless tool hop: \(envelope.tool)]"
        case .none:
            return result.fallbackReply
        }
    }
}
