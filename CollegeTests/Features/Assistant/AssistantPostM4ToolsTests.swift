// AssistantPostM4ToolsTests.swift
// Post-M4 tools + session continuity (Swift Testing).

import Foundation
import Testing
@testable import College

@Suite("Assistant Post-M4 Tools")
struct AssistantPostM4ToolsTests {

    @Test("Should replay cached answer policy trust")
    func shouldReplayCachedAnswerRejectsUntrustedPolicyCache() {
        let untrusted = AssistantReplySource(
            title: "Forum",
            url: "https://reddit.com/r/college",
            kind: .webSearch,
            trustTier: .webGeneral
        )
        #expect(!AssistantFeedbackGovernance.shouldReplayCachedAnswer(
            sources: [untrusted],
            intent: "degree_policy_lookup"
        ))
        let official = AssistantReplySource(
            title: "Registrar",
            url: "https://registrar.edu/policy",
            kind: .webSearch,
            trustTier: .officialWeb
        )
        #expect(AssistantFeedbackGovernance.shouldReplayCachedAnswer(
            sources: [official],
            intent: "degree_policy_lookup"
        ))
    }

    @Test("Session continuity records topics")
    func sessionContinuityRecordsTopics() {
#if DEBUG
        AssistantSessionContinuity.resetForTesting()
        defer { AssistantSessionContinuity.resetForTesting() }
        AssistantSessionContinuity.recordTurn(intent: "career_exploration", userQuery: "What careers fit my major?")
        AssistantSessionContinuity.recordTurn(intent: "degree_policy_lookup", userQuery: "Residency requirement?")
        let block = AssistantSessionContinuity.openingContextBlock()
        #expect(block.contains("career_exploration"))
        #expect(block.contains("degree_policy_lookup"))
#endif
    }

    @Test("Simulate course swap produces themes")
    @MainActor
    func simulateCourseSwapProducesThemes() async throws {
        let tool = SimulateCourseSwapTool()
        let result = try await tool.execute(
            arguments: [
                "removeCourseCode": .string("UIT 101"),
                "addCourseCode": .string("CSE 331")
            ],
            context: AssistantTestFixtures.toolContext()
        )
        #expect(result.ok)
        #expect(result.summary.localizedCaseInsensitiveContains("Simulated swap"))
    }

    @Test("Suggest courses for skill gaps returns payload")
    @MainActor
    func suggestCoursesForSkillGapsReturnsPayload() async throws {
        let tool = SuggestCoursesForSkillGapsTool()
        let result = try await tool.execute(
            arguments: ["skills": .array([.string("security")])],
            context: AssistantTestFixtures.toolContext()
        )
        #expect(result.ok)
    }

    @Test("Assess registration workload heavy credits")
    @MainActor
    func assessRegistrationWorkloadHeavyCredits() async throws {
        let tool = AssessRegistrationWorkloadTool()
        let result = try await tool.execute(
            arguments: ["proposedCredits": .number(19)],
            context: AssistantTestFixtures.toolContext()
        )
        #expect(result.ok)
        #expect(result.summary.localizedCaseInsensitiveContains("heavy"))
    }

    @Test("Requirement risk intent detected")
    func requirementRiskIntentDetected() {
        let frame = AssistantIntentSemantics.intentFrame(
            message: "What's the riskiest unmet requirement for my degree?",
            role: .academicAdvisor
        )
        #expect(frame?.detectedIntent == "requirement_risk")
    }

    @Test("Syllabus deadline sync intent detected")
    func syllabusDeadlineSyncIntentDetected() {
        let frame = AssistantIntentSemantics.intentFrame(
            message: "Add my syllabus deadlines to the planner",
            role: .academicAdvisor
        )
        #expect(frame?.detectedIntent == "syllabus_deadline_sync")
    }
}
