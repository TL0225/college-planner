// StubAssistantInferenceSession.swift
// Feature: Assistant
// Purpose: Assistant module — StubAssistantInferenceSession.
// Data: CollegePersistence / repositories when applicable.

import Foundation

struct StubAssistantInferenceSession: AssistantInferenceSession {
    func plan(request: AssistantPlanningRequest) async -> AssistantPlanningResult {
        let message = request.message.trimmingCharacters(in: .whitespacesAndNewlines)

        if let contextual = Self.contextualStubReply(
            for: message,
            recentConversation: request.recentConversation
        ) {
            return AssistantPlanningResult(
                action: .finalAnswer(contextual),
                fallbackReply: nil,
                failureReason: nil,
                diagnostics: "stub_contextual",
                backend: .stub
            )
        }

        if request.planningToolContext != nil,
           !(request.planningToolContext?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) {
            if Self.isCareerExplorationPrompt(message)
                || (request.planningToolContext?.localizedCaseInsensitiveContains("getStudentLearningProfile") ?? false) {
                let summary = """
                Stub career guidance: based on your learning profile, paths like software engineering, data analysis, and product engineering are common next steps. These are planning ideas, not placement advice.
                """
                return AssistantPlanningResult(
                    action: .finalAnswer(summary),
                    fallbackReply: nil,
                    failureReason: nil,
                    diagnostics: "stub_career_after_tools",
                    backend: .stub
                )
            }
            if Self.isDegreePolicyPrompt(message)
                || (request.planningToolContext?.localizedCaseInsensitiveContains("semanticCatalogSearch") ?? false) {
                let summary = """
                Stub policy answer: residency typically requires 30 in-residence credits. I relied on your catalog/registrar evidence — confirm with your school before changing enrollment.
                """
                return AssistantPlanningResult(
                    action: .finalAnswer(summary),
                    fallbackReply: nil,
                    failureReason: nil,
                    diagnostics: "stub_policy_after_tools",
                    backend: .stub
                )
            }
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

        if Self.isCareerExplorationPrompt(message) {
            return AssistantPlanningResult(
                action: .toolCall(AssistantToolCallEnvelope(tool: "getStudentLearningProfile", arguments: [:])),
                fallbackReply: nil,
                failureReason: nil,
                diagnostics: "stub_career_tool",
                backend: .stub
            )
        }

        if Self.isDegreePolicyPrompt(message) {
            return AssistantPlanningResult(
                action: .toolCall(
                    AssistantToolCallEnvelope(
                        tool: "semanticCatalogSearch",
                        arguments: ["query": .string("residency requirement")]
                    )
                ),
                fallbackReply: nil,
                failureReason: nil,
                diagnostics: "stub_policy_tool",
                backend: .stub
            )
        }

        if Self.isSemesterBreakdownPrompt(message) {
            let summary = """
            Stub semester breakdown: Year 1 — foundations and intro major courses; Year 2 — core requirements; Year 3–4 — electives and capstone. I'll refine this once your catalog and plan are complete.
            """
            return AssistantPlanningResult(
                action: .finalAnswer(summary),
                fallbackReply: nil,
                failureReason: nil,
                diagnostics: "stub_semester_breakdown",
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

        let fallback = "Stub planner: use UITEST_STUB get program progress, career/policy prompts, or UITEST_CONFIRM create task for scripted flows."
        return AssistantPlanningResult(
            action: .finalAnswer(fallback),
            fallbackReply: nil,
            failureReason: nil,
            diagnostics: nil,
            backend: .stub
        )
    }

    private static func isCareerExplorationPrompt(_ message: String) -> Bool {
        let lower = message.lowercased()
        return lower.contains("career")
            || lower.contains("job path")
            || lower.contains("what can i do with")
            || lower.contains("uitest_stub career")
    }

    private static func isDegreePolicyPrompt(_ message: String) -> Bool {
        let lower = message.lowercased()
        return lower.contains("residency")
            || lower.contains("pass/fail")
            || lower.contains("pass fail")
            || lower.contains("degree policy")
            || lower.contains("uitest_stub policy")
    }

    private static func isSemesterBreakdownPrompt(_ message: String) -> Bool {
        let lower = message.lowercased()
        return lower.contains("semester-by-semester")
            || lower.contains("semester by semester")
            || lower.contains("uitest_stub semester breakdown")
    }

    private static func contextualStubReply(for message: String, recentConversation: String?) -> String? {
        let lower = message.lowercased()
        let history = recentConversation?.lowercased() ?? ""

        if lower.contains("fafsa") || lower.contains("aid deadline") || lower.contains("when is fafsa") {
            return "FAFSA filing deadlines vary by state and school year — check your aid office for the official deadline."
        }
        if lower.contains("register") && (lower.contains("ready") || lower.contains("cleared") || lower.contains("hold")) {
            return "Registration readiness depends on holds, prerequisites, and credit limits in your planner."
        }
        if lower.contains("requirement") || lower.contains("graduate") || lower.contains("still need") || lower.contains("prerequisite") {
            return "Your remaining requirement credits and courses are summarized from the degree planner."
        }
        if lower.contains("what is due") || lower.contains("what's due") || lower.contains("due this week") || lower.contains("due tomorrow") {
            return "Upcoming due tasks and assignment deadlines are listed in your planner this week."
        }
        if lower.contains("tomorrow") {
            return "Tomorrow's agenda includes events and due tasks from your planner."
        }
        if lower.contains("this week") {
            return "This week's agenda summarizes events and due tasks from your planner."
        }
        if lower.contains("what's my major") || lower.contains("what is my major") || lower.contains("whats my major") {
            return "Your declared major and program appear on your profile and degree planner."
        }
        if lower.contains("what model") || lower.contains("who are you") {
            return "I'm your College assistant — I help with planning, requirements, and campus tools on-device."
        }
        if history.contains("transfer") || lower.contains("transfer") {
            if history.contains("fall") || lower.contains("fall") {
                return "For fall transfer courses, prioritize major requirements that match your community college credits."
            }
            return "Transfer credit evaluation uses official transcripts and catalog equivalencies."
        }
        if history.contains("fall") || lower.contains("only show fall") || lower.contains("fall courses") {
            return "Fall course options should align with prerequisites and your semester plan."
        }
        if lower.contains("semester") && (lower.contains("plan") || lower.contains("next")) {
            return "Next semester planning should balance prerequisites, target credits, and workload."
        }
        if lower.contains("career") || lower.contains("internship") || lower.contains("job") {
            return "Career paths for your major often include software engineering, analysis, and product roles — planning ideas only."
        }
        if lower.contains("credit") && (lower.contains("heavy") || lower.contains("too much") || lower.contains("load")) {
            return "A heavy credit load can affect workload balance — review registration workload before enrolling."
        }
        return nil
    }
}
