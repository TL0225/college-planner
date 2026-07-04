// AssistantComprehensiveEvaluationTests.swift
// Layer 5 — comprehensive student-style evaluation report (Swift Testing).

import Foundation
import Testing
@testable import College

@Suite("Assistant Comprehensive Evaluation")
struct AssistantComprehensiveEvaluationTests {

    private struct Scenario: Sendable {
        let id: String
        let category: String
        let query: String
        let role: AIAssistantService.Role
        let page: AppPage
        let profile: Profile
        let expectedIntent: String?

        enum Profile: String, Sendable { case empty, seeded }
    }

    private static let emptySnapshot = AssistantTestFixtures.emptySnapshot
    private static let seededSnapshot = AssistantTestFixtures.seededSnapshot

    private static let scenarios: [Scenario] = [
        .init(id: "agenda-week", category: "Schedule", query: "What do I have this week?", role: .academicAdvisor, page: .calendar, profile: .empty, expectedIntent: nil),
        .init(id: "major-seeded", category: "Program", query: "What's my major?", role: .academicAdvisor, page: .academics, profile: .seeded, expectedIntent: nil),
        .init(id: "semester-breakdown", category: "Program", query: "Can you create a semester-by-semester breakdown of my major?", role: .academicAdvisor, page: .academics, profile: .seeded, expectedIntent: "multi_semester_plan"),
        .init(id: "career-with-major", category: "Career", query: "What can I do with my computer science degree?", role: .academicAdvisor, page: .assistant, profile: .seeded, expectedIntent: "career_exploration"),
        .init(id: "policy-residency", category: "Policy", query: "What's the residency requirement for my degree?", role: .academicAdvisor, page: .academics, profile: .seeded, expectedIntent: "degree_policy_lookup"),
        .init(id: "requirement-risk", category: "Program", query: "What's the riskiest unmet requirement for my degree?", role: .academicAdvisor, page: .academics, profile: .seeded, expectedIntent: "requirement_risk"),
        .init(id: "fafsa", category: "Financial aid", query: "When is FAFSA due?", role: .financialAid, page: .assistant, profile: .empty, expectedIntent: nil),
    ]

    @Test("Comprehensive student evaluation records report")
    @MainActor
    func comprehensiveStudentEvaluationRecordsReport() async throws {
        var records: [(scenario: Scenario, intent: String?, routePath: String, reply: String, flags: [String])] = []

        for scenario in Self.scenarios {
            let snapshot = scenario.profile == .seeded ? Self.seededSnapshot : Self.emptySnapshot
            let intent = AssistantIntentSemantics.classify(message: scenario.query, role: scenario.role)?.matchedIntent
            let decision = AIAssistantToolRouter.routeDecision(
                for: scenario.query,
                role: scenario.role,
                snapshot: snapshot,
                activePage: scenario.page
            )
            let routePath: String
            let reply: String
            switch decision {
            case .deterministic(let text):
                routePath = "deterministic"
                reply = text
            case .llmPreferred:
                routePath = "llmPreferred"
                reply = await AssistantHeadlessTurnRunner.previewReply(for: scenario.query) ?? ""
            case .none:
                routePath = "planner"
                reply = await AssistantHeadlessTurnRunner.previewReply(for: scenario.query) ?? ""
            }
            var flags: [String] = []
            if reply.contains("Current programs:\n- Majors:") { flags.append("robotic_program_dump") }
            if let expected = scenario.expectedIntent, intent != expected {
                flags.append("intent_mismatch")
            }
            records.append((scenario, intent, routePath, reply, flags))
        }

        let reportURL = FileManager.default.temporaryDirectory.appendingPathComponent("assistant-evaluation-report.md")
        var lines = ["# Assistant Evaluation", ""]
        for r in records {
            lines.append("## \(r.scenario.id)")
            lines.append("- Intent: \(r.intent ?? "—")")
            lines.append("- Route: \(r.routePath)")
            if !r.flags.isEmpty { lines.append("- Flags: \(r.flags.joined(separator: ", "))") }
            lines.append("")
        }
        try lines.joined(separator: "\n").write(to: reportURL, atomically: true, encoding: .utf8)
        #expect(!records.isEmpty)
    }
}
