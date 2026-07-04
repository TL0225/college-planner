// AIAssistantToolRouterTests.swift
// Layer 2 — router behavior (Swift Testing).

import Foundation
import Testing
@testable import College

@Suite("AI Assistant Tool Router")
struct AIAssistantToolRouterTests {

    @Test("Career question does not deterministic dump")
    @MainActor
    func careerQuestionDoesNotDeterministicDump() {
        let message = "What career does my major lead to?"
        let decision = AIAssistantToolRouter.routeDecision(
            for: message,
            role: .academicAdvisor,
            snapshot: AssistantTestFixtures.emptySnapshot,
            activePage: .academics
        )
        if case .deterministic(let text) = decision {
            #expect(!text.contains("Current programs:"))
            #expect(text.contains("major") || text.contains("Profile"))
        } else if case .llmPreferred = decision {
            // Career should prefer LLM path when major exists
        } else {
            Issue.record("Unexpected route decision for career question")
        }
    }

    @Test("Semester breakdown uses LLM not deterministic dump")
    @MainActor
    func semesterBreakdownUsesLLMNotDeterministicDump() {
        let message = "Can you create a semester by semester breakdown of my major?"
        let decision = AIAssistantToolRouter.routeDecision(
            for: message,
            role: .academicAdvisor,
            snapshot: AssistantTestFixtures.csSnapshot,
            activePage: .academics
        )
        if case .deterministic(let text) = decision {
            Issue.record("Unexpected deterministic: \(text)")
        }
    }

    @Test("Different questions produce different router replies")
    @MainActor
    func byteIdenticalGuardDifferentQuestions() {
        let q1 = "Can you create a semester by semester breakdown of my major?"
        let q2 = "What career does my major lead to?"
        let t1 = AIAssistantToolRouter.reply(
            for: q1, role: .academicAdvisor,
            snapshot: AssistantTestFixtures.emptySnapshot, activePage: .academics
        ) ?? ""
        let t2 = AIAssistantToolRouter.reply(
            for: q2, role: .academicAdvisor,
            snapshot: AssistantTestFixtures.emptySnapshot, activePage: .academics
        ) ?? ""
        if !t1.isEmpty, !t2.isEmpty {
            #expect(t1 != t2)
        }
    }

    @Test("Simple major lookup is fast guided")
    @MainActor
    func simpleMajorLookupIsFastGuided() {
        let decision = AIAssistantToolRouter.routeDecision(
            for: "what's my major",
            role: .academicAdvisor,
            snapshot: AssistantTestFixtures.csSnapshot,
            activePage: .academics
        )
        guard case .deterministic(let text) = decision else {
            Issue.record("Expected deterministic guided lookup")
            return
        }
        #expect(text.contains("Computer Science"))
        #expect(!text.contains("Current programs:\n- Majors:"))
    }

    @Test("What's due empty is guided")
    @MainActor
    func whatsDueEmptyIsGuided() {
        let text = AIAssistantToolRouter.reply(
            for: "what's due this week",
            role: .academicAdvisor,
            snapshot: AssistantTestFixtures.emptySnapshot,
            activePage: .calendar
        )
        #expect(text != nil)
        let body = text ?? ""
        #expect(body.contains("next month") || body.contains("assignment"))
    }

    @Test("Learning profile relevance gate")
    func learningProfileRelevanceGate() {
        let relevant = AssistantLearningProfileBuilder.isMajorRelevantCourse(
            code: "CSE 331",
            title: "Computer Security",
            majorName: "Computer Science",
            requirementCodes: ["CSE 331"]
        )
        #expect(relevant)
    }

    @Test("Simple lookup latency budget")
    @MainActor
    func simpleLookupLatencyBudget() {
        let clock = ContinuousClock()
        let start = clock.now
        _ = AIAssistantToolRouter.reply(
            for: "what's my major",
            role: .academicAdvisor,
            snapshot: AssistantTestFixtures.csSnapshot,
            activePage: .academics
        )
        let elapsed = clock.now - start
        #expect(elapsed <= .milliseconds(800))
    }
}
