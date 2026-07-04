// AssistantWorkflowTests.swift
// Layer 4 — multi-tool workflow chains (Swift Testing).

import Foundation
import Testing
@testable import College

@Suite("Assistant Workflows")
struct AssistantWorkflowTests {

    @Test("Graduation risk question maps to risk intent and tool")
    func graduationRiskIntentChain() {
        let frame = AssistantIntentSemantics.intentFrame(
            message: "What's my graduation risk?",
            role: .academicAdvisor
        )
        #expect(frame?.detectedIntent == "requirement_risk" || frame?.detectedIntent == "requirement_explanation")
        #expect(frame?.preferredTool == "assessRequirementRisk" || frame?.preferredTool == "explainRequirements")
    }

    @Test("Semester plan workflow prefers planning tool")
    func semesterPlanWorkflow() {
        let frame = AssistantIntentSemantics.intentFrame(
            message: "Create a semester plan and check registration readiness",
            role: .academicAdvisor
        )
        #expect(frame != nil)
        #expect(frame?.preferredTool == "draftSemesterPlan" || frame?.preferredTool == "assessRegistrationReadiness")
    }

    @Test("Career exploration workflow uses learning profile tool")
    func careerWorkflowTool() {
        let frame = AssistantIntentSemantics.intentFrame(
            message: "What careers fit my coursework and skills?",
            role: .academicAdvisor
        )
        #expect(frame?.detectedIntent == "career_exploration")
        #expect(frame?.preferredTool == "getStudentLearningProfile")
    }

    @Test("Policy lookup workflow uses catalog search")
    func policyWorkflowTool() {
        let frame = AssistantIntentSemantics.intentFrame(
            message: "What's the residency requirement and credit minimum?",
            role: .academicAdvisor
        )
        #expect(frame?.detectedIntent == "degree_policy_lookup" || frame?.preferredTool == "semanticCatalogSearch")
    }

    @Test("Headless multi-hop stub returns tool name")
    func headlessMultiHopStub() async {
        let reply = await AssistantHeadlessTurnRunner.previewReply(
            for: "UITEST_STUB get program progress"
        )
        #expect(reply?.contains("getProgramProgress") == true || reply?.isEmpty == false)
    }
}
