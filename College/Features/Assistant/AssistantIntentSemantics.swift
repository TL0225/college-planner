// AssistantIntentSemantics.swift
// Feature: Assistant
// Purpose: Assistant module — SemanticRouteSuggestion.
// Data: CollegePersistence / repositories when applicable.

import Foundation

struct SemanticRouteSuggestion: Sendable {
    let decision: AIAssistantToolRouter.RouteDecision
    let confidence: Double
    let matchedIntent: String
}

struct AssistantIntentFrame: Sendable {
    let detectedIntent: String
    let studentGoal: String
    let requiredData: [String]
    let preferredTool: String?
    let fallbackBehavior: String
    let preferredRole: AIAssistantService.Role

    var promptBlock: String {
        """
        Detected intent frame:
        - detectedIntent: \(detectedIntent)
        - studentGoal: \(studentGoal)
        - requiredData: \(requiredData.isEmpty ? "none" : requiredData.joined(separator: ", "))
        - preferredTool: \(preferredTool ?? "none")
        - fallbackBehavior: \(fallbackBehavior)
        - preferredRole: \(preferredRole.rawValue)
        """
    }
}

enum AssistantIntentSemantics {
    static let featureFlagKey = "assistant.semanticRouting.enabled"

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: featureFlagKey) != nil
            ? UserDefaults.standard.bool(forKey: featureFlagKey)
            : true
    }

    static func classify(
        message: String,
        role: AIAssistantService.Role
    ) -> SemanticRouteSuggestion? {

        // 1. Create ML text classifier (Pattern A): NLModel on Neural Engine / GPU / CPU
        if AssistantIntentNLModelSettings.isEnabled {
            let nlStarted = CFAbsoluteTimeGetCurrent()
            if let hit = ProductionIntentClassifier.classify(message: message),
               let nlSuggestion = semanticRouteFromClassifierLabel(
                hit.intentId,
                modelProbability: hit.probability,
                role: role
               ) {
#if DEBUG
                let nlMs = (CFAbsoluteTimeGetCurrent() - nlStarted) * 1000
                DebugLogger.shared.log(
                    "AssistantIntentSemantics route=nlmodel intent=\(hit.intentId) p=\(String(format: "%.3f", hit.probability)) ms=\(Int(nlMs))",
                    category: .intelligence,
                    level: .trace
                )
#endif
                return nlSuggestion
            }
        }

        // 2. Lexical embedding prototypes (Pattern C)
        if AssistantIntentEmbeddingSettings.isEnabled {
            AssistantIntentEmbeddingClassifier.warmUp()
            let embedStarted = CFAbsoluteTimeGetCurrent()
            let threshold = AssistantIntentEmbeddingSettings.similarityThreshold
            let margin = AssistantIntentEmbeddingSettings.minimumIntentMargin
            if let hit = AssistantIntentEmbeddingClassifier.classify(
                message: message,
                threshold: threshold,
                minimumIntentMargin: margin
            ), let suggestion = suggestionForEmbeddedIntent(hit.intentId, role: role) {
#if DEBUG
                let embedMs = (CFAbsoluteTimeGetCurrent() - embedStarted) * 1000
                DebugLogger.shared.log(
                    "AssistantIntentSemantics route=embed intent=\(hit.intentId) score=\(hit.confidence) ms=\(Int(embedMs))",
                    category: .intelligence,
                    level: .trace
                )
#endif
                return suggestion
            }
        }

        let normalized = normalize(message)
        let tokens = tokenSet(normalized)

        guard !tokens.isEmpty else { return nil }

        if matchesAny(normalized, [
            "search the web", "search web", "web search", "look up online",
            "search online", "google", "find online", "find on the web"
        ]) {
            return loggedKeywordRoute(tag: "web_search", SemanticRouteSuggestion(
                decision: .none,
                confidence: 0.86,
                matchedIntent: "web_search"
            ))
        }

        if isFinancialAidPrompt(normalized, tokens: tokens) {
            let intent = financialAidIntent(normalized, tokens: tokens)
            let seed = role == .financialAid ? nil : "Use a financial-aid lens and cite policy sources."
            return loggedKeywordRoute(tag: "financial_aid", SemanticRouteSuggestion(
                decision: .llmPreferred(seed: seed),
                confidence: 0.78,
                matchedIntent: intent
            ))
        }

        if isFirstSemesterPlanningPrompt(normalized, tokens: tokens) {
            return loggedKeywordRoute(tag: "first_semester_plan", SemanticRouteSuggestion(
                decision: .llmPreferred(seed: "Treat this as a first-semester planning request. Draft a safe starter plan or ask for placement/transfer/course availability if exact courses are missing."),
                confidence: 0.88,
                matchedIntent: "first_semester_plan"
            ))
        }

        if isNextSemesterPlanningPrompt(normalized) {
            return loggedKeywordRoute(tag: "next_semester_plan", SemanticRouteSuggestion(
                decision: .llmPreferred(seed: "Treat this as a next-semester planning request. Use planner requirements, prerequisites, target credits, and workload balance."),
                confidence: 0.84,
                matchedIntent: "next_semester_plan"
            ))
        }

        if matchesAny(normalized, ["two semester", "2 semester", "multi semester", "graduation plan", "whole degree", "course sequence", "sequence my courses"]) {
            return loggedKeywordRoute(tag: "multi_semester_plan", SemanticRouteSuggestion(
                decision: .llmPreferred(seed: "Treat this as a multi-semester course sequencing request."),
                confidence: 0.82,
                matchedIntent: "multi_semester_plan"
            ))
        }

        if matchesAny(normalized, ["requirement", "requirements", "degree audit", "what do i still need", "left to graduate", "need for graduation"]) {
            return loggedKeywordRoute(tag: "requirement_explanation", SemanticRouteSuggestion(
                decision: .llmPreferred(seed: "Explain requirements using planner data and avoid calling it an official audit."),
                confidence: 0.8,
                matchedIntent: "requirement_explanation"
            ))
        }

        if matchesAny(normalized, ["registration ready", "ready to register", "register for classes", "registration blocker", "what could stop me"]) {
            return loggedKeywordRoute(tag: "registration_readiness", SemanticRouteSuggestion(
                decision: .llmPreferred(seed: "Assess registration readiness from prerequisites, credits, and planner blockers."),
                confidence: 0.8,
                matchedIntent: "registration_readiness"
            ))
        }

        if matchesAny(normalized, ["study schedule", "weekly schedule", "schedule my week", "plan my week", "work shifts", "around work"]) {
            return loggedKeywordRoute(tag: "weekly_schedule", SemanticRouteSuggestion(
                decision: .llmPreferred(seed: nil),
                confidence: 0.78,
                matchedIntent: "weekly_schedule"
            ))
        }

        if matchesAny(normalized, ["create event", "create an event", "add event", "new event", "add to calendar", "schedule a meeting"]) {
            return loggedKeywordRoute(tag: "event_action", SemanticRouteSuggestion(
                decision: .llmPreferred(seed: nil),
                confidence: 0.78,
                matchedIntent: "event_action"
            ))
        }

        return nil
    }

    static func intentFrame(message: String, role: AIAssistantService.Role) -> AssistantIntentFrame? {
        guard let suggestion = classify(message: message, role: role) else { return nil }
        let preferredRole = preferredRoleForIntent(suggestion.matchedIntent, fallback: role)
        return AssistantIntentFrame(
            detectedIntent: suggestion.matchedIntent,
            studentGoal: studentGoal(for: suggestion.matchedIntent),
            requiredData: requiredData(for: suggestion.matchedIntent),
            preferredTool: preferredTool(for: suggestion.matchedIntent),
            fallbackBehavior: fallbackBehavior(for: suggestion.matchedIntent),
            preferredRole: preferredRole
        )
    }

    static func intentPromptBlock(message: String, role: AIAssistantService.Role) -> String {
        intentFrame(message: message, role: role)?.promptBlock ?? """
        Detected intent frame:
        - detectedIntent: unknown
        - studentGoal: infer from the full user message and recent conversation
        - requiredData: ask only for missing data needed to answer safely
        - preferredTool: choose from available tools when app-backed data is needed
        - fallbackBehavior: provide a useful answer from available context and state what is missing
        - preferredRole: \(role.rawValue)
        """
    }

    static func inferredRole(message: String, fallback: AIAssistantService.Role = .academicAdvisor) -> AIAssistantService.Role {
        guard let frame = intentFrame(message: message, role: fallback) else { return fallback }
        return frame.preferredRole
    }

    static func inferredAgentRole(message: String, fallback: AssistantAgentRole = .academicAdvisor) -> AssistantAgentRole {
        switch inferredRole(message: message, fallback: fallback == .academicAdvisor ? .academicAdvisor : .financialAid) {
        case .academicAdvisor:
            return .academicAdvisor
        case .financialAid:
            return .financialAid
        }
    }

    static func isFirstSemesterPlanningPrompt(_ normalized: String, tokens: Set<String>? = nil) -> Bool {
        let t = tokens ?? tokenSet(normalized)
        if matchesAny(normalized, [
            "first semester", "1st semester", "freshman schedule", "freshman semester",
            "first term", "starting classes", "classes to start", "what classes should i take first",
            "what should i take first", "new student", "incoming student", "start my degree",
            "begin my degree", "first year schedule", "first-year schedule"
        ]) {
            return true
        }
        return (t.contains("first") || t.contains("freshman") || t.contains("start") || t.contains("starting") || t.contains("new"))
            && (t.contains("semester") || t.contains("classes") || t.contains("clases") || t.contains("courses") || t.contains("schedule") || t.contains("major"))
            && (t.contains("plan") || t.contains("take") || t.contains("build") || t.contains("make") || t.contains("choose") || t.contains("should"))
    }

    private static func isNextSemesterPlanningPrompt(_ normalized: String) -> Bool {
        matchesAny(normalized, [
            "next semester", "next-semester", "next term", "upcoming semester",
            "plan a semester", "plan my semester", "semester plan", "course plan"
        ])
    }

    private static func isFinancialAidPrompt(_ normalized: String, tokens: Set<String>) -> Bool {
        matchesAny(normalized, [
            "financial aid", "fafsa", "tap", "pell", "sap", "satisfactory academic progress",
            "aid package", "award letter", "student aid", "tuition assistance", "state aid",
            "dependency status", "verification", "fsa id", "enrollment intensity",
            "cal grant", "csac", "bright futures", "hope scholarship", "state grant"
        ]) || (tokens.contains("aid") && (tokens.contains("money") || tokens.contains("eligible") || tokens.contains("eligibility") || tokens.contains("full") || tokens.contains("time") || tokens.contains("credits")))
    }

    private static func financialAidIntent(_ normalized: String, tokens: Set<String>) -> String {
        if normalized.contains("estimate") || normalized.contains("how much") || tokens.contains("money") {
            return "aid_estimate"
        }
        if normalized.contains("full time") ||
            normalized.contains("full-time") ||
            normalized.contains("part time") ||
            normalized.contains("part-time") ||
            normalized.contains("enrollment intensity") ||
            normalized.contains("below 12") ||
            (tokens.contains("drop") && tokens.contains("credits")) ||
            (tokens.contains("dropping") && tokens.contains("credits")) {
            return "enrollment_intensity"
        }
        if normalized.contains("fafsa") || normalized.contains("fsa id") || normalized.contains("dependency status") || normalized.contains("verification") {
            return "fafsa_help"
        }
        if normalized.contains("tap") ||
            normalized.contains("hesc") ||
            normalized.contains("state aid") ||
            normalized.contains("cal grant") ||
            normalized.contains("csac") ||
            normalized.contains("bright futures") ||
            normalized.contains("hope scholarship") ||
            normalized.contains("state grant") {
            return "state_aid_help"
        }
        if normalized.contains("sap") || normalized.contains("satisfactory academic progress") {
            return "sap_risk"
        }
        if normalized.contains("award letter") || normalized.contains("offer letter") || normalized.contains("uploaded aid") || normalized.contains("aid document") {
            return "award_letter_review"
        }
        return "financial_aid"
    }

    private static func preferredRoleForIntent(_ intent: String, fallback: AIAssistantService.Role) -> AIAssistantService.Role {
        switch intent {
        case "financial_aid", "fafsa_help", "state_aid_help", "sap_risk", "aid_estimate", "award_letter_review", "enrollment_intensity":
            return .financialAid
        default:
            return fallback
        }
    }

    private static func studentGoal(for intent: String) -> String {
        switch intent {
        case "first_semester_plan":
            return "Create a safe first-semester starter plan from degree context."
        case "next_semester_plan":
            return "Draft a balanced next-semester plan."
        case "multi_semester_plan":
            return "Sequence courses across multiple semesters."
        case "requirement_explanation":
            return "Explain remaining requirements in plain language."
        case "registration_readiness":
            return "Identify blockers before registration."
        case "weekly_schedule":
            return "Draft a study or weekly schedule."
        case "fafsa_help":
            return "Explain FAFSA concepts and next steps."
        case "state_aid_help":
            return "Explain state aid concepts and next steps."
        case "sap_risk":
            return "Explain SAP risk and actions."
        case "aid_estimate":
            return "Frame a non-official aid estimate."
        case "award_letter_review":
            return "Review an aid document or award-letter facts."
        case "enrollment_intensity":
            return "Connect planned credits to aid enrollment risk."
        default:
            return "Infer the student's goal from the full message."
        }
    }

    private static func requiredData(for intent: String) -> [String] {
        switch intent {
        case "first_semester_plan":
            return ["target credits", "placement or transfer/AP credits", "available course list", "program requirements"]
        case "next_semester_plan", "multi_semester_plan":
            return ["target credits", "remaining requirements", "prerequisites", "course availability"]
        case "weekly_schedule":
            return ["classes", "work blocks", "due dates", "preferred study times"]
        case "aid_estimate":
            return ["SAI", "cost of attendance", "enrollment credits", "known grants"]
        case "award_letter_review":
            return ["uploaded award letter or pasted aid details"]
        case "enrollment_intensity":
            return ["planned credits", "school full-time threshold"]
        default:
            return []
        }
    }

    private static func preferredTool(for intent: String) -> String? {
        switch intent {
        case "first_semester_plan", "next_semester_plan", "multi_semester_plan":
            return "draftSemesterPlan"
        case "requirement_explanation":
            return "explainRequirements"
        case "registration_readiness":
            return "assessRegistrationReadiness"
        case "weekly_schedule":
            return "draftWeeklySchedule"
        case "fafsa_help", "state_aid_help":
            return "getAidDeadlines"
        case "sap_risk":
            return "explainSAPPolicy"
        case "aid_estimate":
            return "estimateAidRange"
        case "award_letter_review":
            return "extractAidDocumentFacts"
        case "enrollment_intensity":
            return "getFullTimeStatus"
        default:
            return nil
        }
    }

    private static func fallbackBehavior(for intent: String) -> String {
        switch intent {
        case "first_semester_plan":
            return "If exact courses are unavailable, provide a safe 12-15 credit starter template and list missing data."
        case "next_semester_plan", "multi_semester_plan":
            return "Use planner context to draft sequencing guidance and state missing course availability or prerequisite data."
        case "aid_estimate":
            return "Do not invent award amounts; explain missing inputs and non-official estimate limits."
        case "fafsa_help", "state_aid_help", "sap_risk", "award_letter_review", "enrollment_intensity":
            return "Give conceptual guidance, cite tool/web sources when available, and avoid official determinations."
        default:
            return "Give the best grounded answer available and ask focused follow-up questions for missing data."
        }
    }

    private static func normalize(_ message: String) -> String {
        message
            .lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func tokenSet(_ normalized: String) -> Set<String> {
        Set(
            normalized
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
    }

    private static func matchesAny(_ normalized: String, _ phrases: [String]) -> Bool {
        phrases.contains { normalized.contains($0) }
    }

    /// Build a route from Create ML label; reuses embedding/keyword ``decision`` presets with NL probability as confidence.
    private static func semanticRouteFromClassifierLabel(
        _ intentId: String,
        modelProbability: Double,
        role: AIAssistantService.Role
    ) -> SemanticRouteSuggestion? {
        guard let base = suggestionForEmbeddedIntent(intentId, role: role) else { return nil }
        let p = min(1.0, max(0.0, modelProbability))
        return SemanticRouteSuggestion(
            decision: base.decision,
            confidence: p,
            matchedIntent: intentId
        )
    }

#if DEBUG
    private static func loggedKeywordRoute(tag: String, _ suggestion: SemanticRouteSuggestion) -> SemanticRouteSuggestion {
        DebugLogger.shared.log(
            "AssistantIntentSemantics route=keyword tag=\(tag) intent=\(suggestion.matchedIntent)",
            category: .intelligence,
            level: .trace
        )
        return suggestion
    }
#else
    private static func loggedKeywordRoute(tag: String, _ suggestion: SemanticRouteSuggestion) -> SemanticRouteSuggestion {
        suggestion
    }
#endif

    /// Mirrors keyword-branch ``SemanticRouteSuggestion``s for embedding-routed intents (keep in sync when editing classify).
    private static func suggestionForEmbeddedIntent(
        _ intentId: String,
        role: AIAssistantService.Role
    ) -> SemanticRouteSuggestion? {
        switch intentId {
        case "web_search":
            return SemanticRouteSuggestion(
                decision: .none,
                confidence: 0.86,
                matchedIntent: "web_search"
            )
        case "first_semester_plan":
            return SemanticRouteSuggestion(
                decision: .llmPreferred(seed: "Treat this as a first-semester planning request. Draft a safe starter plan or ask for placement/transfer/course availability if exact courses are missing."),
                confidence: 0.88,
                matchedIntent: "first_semester_plan"
            )
        case "next_semester_plan":
            return SemanticRouteSuggestion(
                decision: .llmPreferred(seed: "Treat this as a next-semester planning request. Use planner requirements, prerequisites, target credits, and workload balance."),
                confidence: 0.84,
                matchedIntent: "next_semester_plan"
            )
        case "multi_semester_plan":
            return SemanticRouteSuggestion(
                decision: .llmPreferred(seed: "Treat this as a multi-semester course sequencing request."),
                confidence: 0.82,
                matchedIntent: "multi_semester_plan"
            )
        case "requirement_explanation":
            return SemanticRouteSuggestion(
                decision: .llmPreferred(seed: "Explain requirements using planner data and avoid calling it an official audit."),
                confidence: 0.8,
                matchedIntent: "requirement_explanation"
            )
        case "registration_readiness":
            return SemanticRouteSuggestion(
                decision: .llmPreferred(seed: "Assess registration readiness from prerequisites, credits, and planner blockers."),
                confidence: 0.8,
                matchedIntent: "registration_readiness"
            )
        case "weekly_schedule":
            return SemanticRouteSuggestion(
                decision: .llmPreferred(seed: nil),
                confidence: 0.78,
                matchedIntent: "weekly_schedule"
            )
        case "event_action":
            return SemanticRouteSuggestion(
                decision: .llmPreferred(seed: nil),
                confidence: 0.78,
                matchedIntent: "event_action"
            )
        case "fafsa_help", "state_aid_help", "sap_risk", "aid_estimate", "award_letter_review", "enrollment_intensity", "financial_aid":
            let seed = role == .financialAid ? nil : "Use a financial-aid lens and cite policy sources."
            return SemanticRouteSuggestion(
                decision: .llmPreferred(seed: seed),
                confidence: 0.78,
                matchedIntent: intentId
            )
        default:
            return nil
        }
    }
}
