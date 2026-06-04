// AssistantInferenceSession.swift
// Feature: Assistant
// Purpose: Assistant module — AssistantPlanningRequest.
// Data: CollegePersistence / repositories when applicable.

import Foundation

protocol AssistantInferenceSession: Sendable {
    func plan(request: AssistantPlanningRequest) async -> AssistantPlanningResult
}

struct AssistantPlanningRequest: Sendable {
    let message: String
    let role: AIAssistantService.Role
    let contextSummary: String
    let recentConversation: String?
    let persona: AssistantPersona
    let allowedToolNames: Set<String>
    let planningToolContext: String?
    let attachmentContextBlock: String?
    let policyContext: AssistantPolicyContext?
    let toolDescriptors: [AssistantToolDescriptor]
    let toolCatalogJSON: String
}

struct AssistantPlanningResult: Sendable {
    let action: AssistantModelAction?
    let fallbackReply: String?
    let failureReason: AIAssistantService.FailureReason?
    let diagnostics: String?
    let backend: AssistantInferenceBackend
}
