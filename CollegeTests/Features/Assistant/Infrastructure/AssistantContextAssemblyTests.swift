// AssistantContextAssemblyTests.swift
// Layer 0 — memory assembly and context budget (Swift Testing).

import Foundation
import Testing
@testable import College

@Suite("Assistant Context Assembly")
struct AssistantContextAssemblyTests {

    @Test("Profile layer included in assembled context")
    func profileLayerIncluded() {
        let profile = AssistantMinimalProfileContext(
            role: "Academic Advisor",
            activePage: "academics",
            university: "Example U",
            degreeLevel: "Undergraduate",
            degreeType: "BS",
            majors: ["UITest Computer Science"],
            minors: [],
            creditsEarned: 45,
            creditsRequired: 120,
            gpa: 3.4,
            expectedGraduation: "2028",
            todayISO: "2026-06-19",
            aidJurisdictionLine: nil
        )
        let budget = AssistantContextBudget.forLengthPreset("balanced")
        let assembled = AssistantContextAssembler.assemble(
            minimalProfile: profile,
            plannerRAGBlock: "Planned: CSE 331 Computer Security",
            webMemoryBlock: "",
            policyRAGBlock: nil,
            handbookBlock: nil,
            rollingSummaryBlock: nil,
            coldFallbackBlock: nil,
            budget: budget,
            lengthPreset: nil
        )
        #expect(assembled.contains("UITest Computer Science"))
        #expect(assembled.contains("CSE 331") || assembled.contains("Computer Security"))
    }

    @Test("Context truncates when exceeding budget ceiling")
    func contextTruncatesWhenExceedingBudget() {
        let profile = AssistantMinimalProfileContext(
            role: "Academic Advisor",
            activePage: "assistant",
            university: "U",
            degreeLevel: nil,
            degreeType: nil,
            majors: ["Major"],
            minors: [],
            creditsEarned: 0,
            creditsRequired: 120,
            gpa: nil,
            expectedGraduation: nil,
            todayISO: "2026-06-19",
            aidJurisdictionLine: nil
        )
        let hugePlanner = String(repeating: "Planner context line.\n", count: 500)
        var budget = AssistantContextBudget.forLengthPreset("short")
        let assembled = AssistantContextAssembler.assemble(
            minimalProfile: profile,
            plannerRAGBlock: hugePlanner,
            webMemoryBlock: "",
            policyRAGBlock: nil,
            handbookBlock: nil,
            rollingSummaryBlock: nil,
            coldFallbackBlock: nil,
            budget: budget,
            lengthPreset: "short"
        )
        #expect(assembled.count <= budget.contextSummaryCeilingChars + 30)
    }

    @Test("Learning profile includes major-relevant courses")
    @MainActor
    func learningProfileIncludesMajorRelevantCourses() {
        let profile = AssistantLearningProfileBuilder.build(
            persistence: CollegePersistence.shared,
            majorNames: ["UITest Computer Science"],
            programURL: nil
        )
        #expect(!profile.compressedSummary.isEmpty)
    }
}
