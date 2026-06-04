// JsonWorkerAssistantSession.swift
// Feature: Assistant
// Purpose: Assistant module — JsonWorkerAssistantSession.
// Data: CollegePersistence / repositories when applicable.

import Foundation

struct JsonWorkerAssistantSession: AssistantInferenceSession {
    func plan(request: AssistantPlanningRequest) async -> AssistantPlanningResult {
        let outcome = await AIAssistantService.shared.localJsonWorkerPlan(request: request)
        return AssistantPlanningResult(
            action: outcome.action,
            fallbackReply: outcome.fallbackReply,
            failureReason: outcome.failureReason,
            diagnostics: outcome.diagnostics,
            backend: .jsonWorker
        )
    }
}
