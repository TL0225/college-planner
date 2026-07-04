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

    /// Intents that must win over legacy router keyword shortcuts (e.g. bare `major` dump).
    static func shouldShortCircuitRouter(_ suggestion: SemanticRouteSuggestion) -> Bool {
        guard suggestion.confidence >= 0.7 else { return false }
        switch suggestion.matchedIntent {
        case "career_exploration", "degree_policy_lookup", "multi_semester_plan",
             "first_semester_plan", "next_semester_plan", "requirement_explanation",
             "registration_readiness", "web_search":
            return true
        default:
            return false
        }
    }

    static func classify(
        message: String,
        role: AIAssistantService.Role
    ) -> SemanticRouteSuggestion? {
        let normalized = normalize(message)
        let tokens = tokenSet(normalized)
        guard !tokens.isEmpty else { return nil }

        if let specific = classifyHighSpecificityIntents(normalized: normalized, role: role) {
            return specific
        }

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

        if matchesAny(normalized, ["two semester", "2 semester", "multi semester", "graduation plan", "whole degree", "course sequence", "sequence my courses",
                                   "degree timeline", "timeline by semester", "semester breakdown", "double major"]) {
            return loggedKeywordRoute(tag: "multi_semester_plan", SemanticRouteSuggestion(
                decision: .llmPreferred(seed: "Treat this as a multi-semester course sequencing request."),
                confidence: 0.82,
                matchedIntent: "multi_semester_plan"
            ))
        }

        if matchesAny(normalized, ["requirement", "requirements", "degree audit", "what do i still need", "left to graduate", "need for graduation",
                                   "credits do i have left", "credits left", "on track to graduate", "graduate early"]) {
            return loggedKeywordRoute(tag: "requirement_explanation", SemanticRouteSuggestion(
                decision: .llmPreferred(seed: "Explain requirements using planner data and avoid calling it an official audit."),
                confidence: 0.8,
                matchedIntent: "requirement_explanation"
            ))
        }

        if AssistantFeatureFlags.degreePolicyLookupEnabled,
           matchesAny(normalized, [
               "policy", "policies", "residency", "pass fail", "pass/fail", "grade replacement",
               "academic standing", "catalog says", "registrar", "official rule", "degree require"
           ]) {
            return loggedKeywordRoute(tag: "degree_policy_lookup", SemanticRouteSuggestion(
                decision: .llmPreferred(seed: "Use semanticCatalogSearch and policy evidence; cite official catalog sources. Official catalog supersedes this assistant."),
                confidence: 0.82,
                matchedIntent: "degree_policy_lookup"
            ))
        }

        if AssistantFeatureFlags.careerExplorationEnabled,
           matchesAny(normalized, [
               "career", "careers", "job path", "lead to", "what can i do with", "work in",
               "profession", "industry", "roles for my major", "jobs fit", "graduates work", "internship"
           ]) {
            return loggedKeywordRoute(tag: "career_exploration", SemanticRouteSuggestion(
                decision: .llmPreferred(seed: AssistantCareerReplyGuide.plannerSeed),
                confidence: 0.85,
                matchedIntent: "career_exploration"
            ))
        }

        if matchesAny(normalized, ["registration ready", "ready to register", "register for classes", "registration blocker", "what could stop me",
                                   "registration hold", "hold check"]) {
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

        if let supplemental = classifySupplementalKeywords(normalized: normalized, tokens: tokens, role: role) {
            return supplemental
        }

        return nil
    }

    /// Keyword routes for corpus gaps not covered by NL/embedding or high-specificity matchers.
    private static func classifySupplementalKeywords(
        normalized: String,
        tokens: Set<String>,
        role: AIAssistantService.Role
    ) -> SemanticRouteSuggestion? {
        if matchesAny(normalized, [
            "what is due", "what's due", "due this week", "due tomorrow", "due today", "what do i have this week"
        ]) {
            return loggedKeywordRoute(tag: "planner_due_lookup", SemanticRouteSuggestion(
                decision: .llmPreferred(seed: "Summarize open planner tasks and due dates from app data."),
                confidence: 0.84,
                matchedIntent: "planner_due_lookup"
            ))
        }

        if AIAssistantToolRouter.isSimpleProgramLookup(normalized)
            || matchesAny(normalized, ["what's my major", "what is my major", "whats my major", "declared major"]) {
            return loggedKeywordRoute(tag: "program_lookup", SemanticRouteSuggestion(
                decision: .llmPreferred(seed: "Answer from declared majors/minors in profile data."),
                confidence: 0.88,
                matchedIntent: "program_lookup"
            ))
        }

        if matchesAny(normalized, ["navigate to", "go to the", "open the", "show me the"])
            && matchesAny(normalized, ["academics", "calendar", "career", "degree", "assistant", "page", "tab"]) {
            return loggedKeywordRoute(tag: "page_navigation", SemanticRouteSuggestion(
                decision: .llmPreferred(seed: "Use navigateToPage when the student asks to open a section."),
                confidence: 0.8,
                matchedIntent: "page_navigation"
            ))
        }

        if matchesAny(normalized, ["find courses about", "find courses on", "courses about", "course about"]) {
            return loggedKeywordRoute(tag: "catalog_course_search", SemanticRouteSuggestion(
                decision: .llmPreferred(seed: "Use semanticCatalogSearch for topical course discovery."),
                confidence: 0.82,
                matchedIntent: "catalog_course_search"
            ))
        }

        if matchesAny(normalized, ["add assignment", "assignment due", "create task", "create a task"]) {
            return loggedKeywordRoute(tag: "task_creation", SemanticRouteSuggestion(
                decision: .llmPreferred(seed: "Use createTask or updateTask after confirming title and due date."),
                confidence: 0.8,
                matchedIntent: "task_creation"
            ))
        }

        if matchesAny(normalized, ["what model are you", "which model", "who are you", "what llm", "what ai"]) {
            return loggedKeywordRoute(tag: "general_inquiry", SemanticRouteSuggestion(
                decision: .llmPreferred(seed: "Answer briefly about capabilities; do not claim official registrar authority."),
                confidence: 0.75,
                matchedIntent: "general_inquiry"
            ))
        }

        if matchesAny(normalized, [
            "credits do i have left", "credits left", "credits remaining", "how many credits",
            "on track to graduate", "on track to grad", "graduate early", "graduation early",
            "transfer credit", "transfer credits", "transfer evaluation",
            "understand prerequisites", "help me understand prerequisites",
            "clasess do i need", "need to gradute", "still need to gradute"
        ]) || (tokens.contains("prerequisite") || tokens.contains("prerequisites")) {
            return loggedKeywordRoute(tag: "requirement_explanation", SemanticRouteSuggestion(
                decision: .llmPreferred(seed: "Explain requirements using planner data and avoid calling it an official audit."),
                confidence: 0.8,
                matchedIntent: "requirement_explanation"
            ))
        }

        if matchesAny(normalized, [
            "degree timeline", "timeline by semester", "full degree timeline", "semester breakdown",
            "double major"
        ]) {
            return loggedKeywordRoute(tag: "multi_semester_plan", SemanticRouteSuggestion(
                decision: .llmPreferred(seed: "Treat this as a multi-semester course sequencing request."),
                confidence: 0.82,
                matchedIntent: "multi_semester_plan"
            ))
        }

        if matchesAny(normalized, [
            "spring schedule", "fall schedule", "plan my spring", "plan my fall", "plan nxt semster", "nxt semster"
        ]) || (normalized.contains("plan") && normalized.contains("semster")) {
            return loggedKeywordRoute(tag: "next_semester_plan", SemanticRouteSuggestion(
                decision: .llmPreferred(seed: "Treat this as a next-semester planning request. Use planner requirements, prerequisites, target credits, and workload balance."),
                confidence: 0.84,
                matchedIntent: "next_semester_plan"
            ))
        }

        if matchesAny(normalized, [
            "freshman year", "pick freshman", "first sem courses", "first sem "
        ]) || (tokens.contains("freshman") && (tokens.contains("courses") || tokens.contains("pick"))) {
            return loggedKeywordRoute(tag: "first_semester_plan", SemanticRouteSuggestion(
                decision: .llmPreferred(seed: "Treat this as a first-semester planning request. Draft a safe starter plan or ask for placement/transfer/course availability if exact courses are missing."),
                confidence: 0.88,
                matchedIntent: "first_semester_plan"
            ))
        }

        if matchesAny(normalized, [
            "jobs fit my degree", "fit my degree", "graduates work", "where do", "internship", "internships",
            "careeer options", "career options"
        ]) {
            return loggedKeywordRoute(tag: "career_exploration", SemanticRouteSuggestion(
                decision: .llmPreferred(seed: AssistantCareerReplyGuide.plannerSeed),
                confidence: 0.85,
                matchedIntent: "career_exploration"
            ))
        }

        if matchesAny(normalized, ["registration hold", "hold check"]) {
            return loggedKeywordRoute(tag: "registration_readiness", SemanticRouteSuggestion(
                decision: .llmPreferred(seed: "Assess registration readiness from prerequisites, credits, and planner blockers."),
                confidence: 0.8,
                matchedIntent: "registration_readiness"
            ))
        }

        if matchesAny(normalized, ["dropping one course", "adding another", "drop one course and add"]) {
            return loggedKeywordRoute(tag: "course_swap_simulation", SemanticRouteSuggestion(
                decision: .llmPreferred(seed: "Use simulateCourseSwap for what-if analysis only."),
                confidence: 0.8,
                matchedIntent: "course_swap_simulation"
            ))
        }

        if matchesAny(normalized, ["courses for cybersecurity", "cybersecurity skills", "courses for skills"]) {
            return loggedKeywordRoute(tag: "skill_gap_bridge", SemanticRouteSuggestion(
                decision: .llmPreferred(seed: "Use suggestCoursesForSkillGaps with job-match skills."),
                confidence: 0.8,
                matchedIntent: "skill_gap_bridge"
            ))
        }

        if matchesAny(normalized, [
            "electives count toward", "which electives count"
        ]) {
            return loggedKeywordRoute(tag: "degree_policy_lookup", SemanticRouteSuggestion(
                decision: .llmPreferred(seed: "Use semanticCatalogSearch and policy evidence; cite official catalog sources."),
                confidence: 0.82,
                matchedIntent: "degree_policy_lookup"
            ))
        }

        if matchesAny(normalized, ["study session", "add study session"]) {
            return loggedKeywordRoute(tag: "event_action", SemanticRouteSuggestion(
                decision: .llmPreferred(seed: nil),
                confidence: 0.78,
                matchedIntent: "event_action"
            ))
        }

        _ = role
        return nil
    }

    /// Narrow intents that must win over NL/embedding and broad keyword routes (e.g. bare `requirement`).
    private static func classifyHighSpecificityIntents(
        normalized: String,
        role _: AIAssistantService.Role
    ) -> SemanticRouteSuggestion? {
        if matchesAny(normalized, ["riskiest requirement", "riskiest unmet", "graduation risk", "requirement risk", "risky unmet"]) {
            return loggedKeywordRoute(tag: "requirement_risk", SemanticRouteSuggestion(
                decision: .llmPreferred(seed: "Use assessRequirementRisk to rank unmet requirements."),
                confidence: 0.82,
                matchedIntent: "requirement_risk"
            ))
        }

        if matchesAny(normalized, ["swap", "what if i take", "instead of", "simulate course", "dropping one course", "adding another"]) {
            return loggedKeywordRoute(tag: "course_swap_simulation", SemanticRouteSuggestion(
                decision: .llmPreferred(seed: "Use simulateCourseSwap for what-if analysis only."),
                confidence: 0.8,
                matchedIntent: "course_swap_simulation"
            ))
        }

        if matchesAny(normalized, ["syllabus deadline", "syllabus deadlines", "syllabus due", "sync syllabus", "add syllabus", "add my syllabus"]) {
            return loggedKeywordRoute(tag: "syllabus_deadline_sync", SemanticRouteSuggestion(
                decision: .llmPreferred(seed: "Use proposeSyllabusDeadlineSync then syncSyllabusDeadlinesToPlanner after user confirms."),
                confidence: 0.82,
                matchedIntent: "syllabus_deadline_sync"
            ))
        }

        if matchesAny(normalized, ["skill gap", "courses for skills", "bridge skills", "learn security", "learn python",
                                   "courses for cybersecurity", "cybersecurity skills"]) {
            return loggedKeywordRoute(tag: "skill_gap_bridge", SemanticRouteSuggestion(
                decision: .llmPreferred(seed: "Use suggestCoursesForSkillGaps with job-match skills."),
                confidence: 0.8,
                matchedIntent: "skill_gap_bridge"
            ))
        }

        if matchesAny(normalized, ["registration workload", "heavy semester", "credit load", "too many credits",
                                   "credits too heavy", "course load too much", "course load", "crdits too much"]) {
            return loggedKeywordRoute(tag: "registration_workload", SemanticRouteSuggestion(
                decision: .llmPreferred(seed: "Use assessRegistrationWorkload before registering."),
                confidence: 0.8,
                matchedIntent: "registration_workload"
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
            "plan a semester", "plan my semester", "semester plan", "course plan",
            "spring schedule", "fall schedule", "plan my spring", "plan my fall"
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
        case "career_exploration":
            return "Explore career paths grounded in major and coursework."
        case "degree_policy_lookup":
            return "Answer degree policy questions from catalog and official sources."
        case "requirement_explanation":
            return "Explain remaining requirements in plain language."
        case "registration_readiness":
            return "Identify blockers before registration."
        case "requirement_risk":
            return "Rank unmet requirements by graduation risk."
        case "course_swap_simulation":
            return "Compare a hypothetical course swap on learning themes."
        case "syllabus_deadline_sync":
            return "Draft planner tasks from syllabus due dates."
        case "skill_gap_bridge":
            return "Suggest catalog courses that close career skill gaps."
        case "registration_workload":
            return "Warn when a proposed credit load looks heavy."
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
        case "planner_due_lookup":
            return "Summarize upcoming planner tasks and due dates."
        case "program_lookup":
            return "State declared majors and minors from profile data."
        case "page_navigation":
            return "Open the requested app section."
        case "catalog_course_search":
            return "Find catalog courses matching a topic."
        case "task_creation":
            return "Draft or confirm a planner task with due date."
        case "general_inquiry":
            return "Answer meta questions about assistant capabilities."
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
        case "career_exploration":
            return ["declared major", "planned courses", "optional web for baseline roles"]
        case "degree_policy_lookup":
            return ["synced catalog", "program identity", "official policy URLs"]
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
        case "career_exploration":
            return "getStudentLearningProfile"
        case "registration_readiness":
            return "assessRegistrationReadiness"
        case "requirement_risk":
            return "assessRequirementRisk"
        case "course_swap_simulation":
            return "simulateCourseSwap"
        case "syllabus_deadline_sync":
            return "proposeSyllabusDeadlineSync"
        case "skill_gap_bridge":
            return "suggestCoursesForSkillGaps"
        case "registration_workload":
            return "assessRegistrationWorkload"
        case "weekly_schedule":
            return "draftWeeklySchedule"
        case "web_search":
            return "searxWebSearch"
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
        case "catalog_course_search", "degree_policy_lookup":
            return "semanticCatalogSearch"
        case "program_lookup":
            return "getStudentProfile"
        case "page_navigation":
            return "navigateToPage"
        case "task_creation":
            return "createTask"
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
        case "career_exploration":
            return "Use getStudentLearningProfile; if major missing use guided steps; never claim placement."
        case "degree_policy_lookup":
            return "Prefer catalog search and policy RAG; official catalog supersedes assistant."
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
        case "career_exploration":
            return SemanticRouteSuggestion(
                decision: .llmPreferred(seed: AssistantCareerReplyGuide.plannerSeed),
                confidence: 0.85,
                matchedIntent: "career_exploration"
            )
        case "degree_policy_lookup":
            return SemanticRouteSuggestion(
                decision: .llmPreferred(seed: "Use semanticCatalogSearch and policy evidence; cite official sources."),
                confidence: 0.82,
                matchedIntent: "degree_policy_lookup"
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
        case "requirement_risk":
            return SemanticRouteSuggestion(
                decision: .llmPreferred(seed: "Use assessRequirementRisk to rank unmet requirements."),
                confidence: 0.82,
                matchedIntent: "requirement_risk"
            )
        case "course_swap_simulation":
            return SemanticRouteSuggestion(
                decision: .llmPreferred(seed: "Use simulateCourseSwap for what-if analysis only."),
                confidence: 0.8,
                matchedIntent: "course_swap_simulation"
            )
        case "syllabus_deadline_sync":
            return SemanticRouteSuggestion(
                decision: .llmPreferred(seed: "Use proposeSyllabusDeadlineSync then syncSyllabusDeadlinesToPlanner after user confirms."),
                confidence: 0.82,
                matchedIntent: "syllabus_deadline_sync"
            )
        case "skill_gap_bridge":
            return SemanticRouteSuggestion(
                decision: .llmPreferred(seed: "Use suggestCoursesForSkillGaps with job-match skills."),
                confidence: 0.8,
                matchedIntent: "skill_gap_bridge"
            )
        case "registration_workload":
            return SemanticRouteSuggestion(
                decision: .llmPreferred(seed: "Use assessRegistrationWorkload before registering."),
                confidence: 0.8,
                matchedIntent: "registration_workload"
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
