// AssistantToolExecutionTests.swift
// Layer 3 — top tool edge matrices (Swift Testing).

import Foundation
import Testing
@testable import College

@Suite("Assistant Tool Execution")
struct AssistantToolExecutionTests {

    @Test("Assess registration workload flags heavy credits")
    @MainActor
    func assessRegistrationWorkloadHeavy() async throws {
        let tool = AssessRegistrationWorkloadTool()
        let result = try await tool.execute(
            arguments: ["proposedCredits": .number(19)],
            context: AssistantTestFixtures.toolContext()
        )
        #expect(result.ok)
        #expect(result.summary.localizedCaseInsensitiveContains("heavy"))
    }

    @Test("Simulate course swap returns diff summary")
    @MainActor
    func simulateCourseSwap() async throws {
        let tool = SimulateCourseSwapTool()
        let result = try await tool.execute(
            arguments: [
                "removeCourseCode": .string("UIT 101"),
                "addCourseCode": .string("CSE 331")
            ],
            context: AssistantTestFixtures.toolContext()
        )
        #expect(result.ok)
        #expect(!result.summary.isEmpty)
    }

    @Test("Suggest courses for skill gaps accepts skills array")
    @MainActor
    func suggestCoursesForSkillGaps() async throws {
        let tool = SuggestCoursesForSkillGapsTool()
        let result = try await tool.execute(
            arguments: ["skills": .array([.string("security"), .string("networking")])],
            context: AssistantTestFixtures.toolContext()
        )
        #expect(result.ok)
    }

    @Test("Navigate rejects LMS page slug")
    @MainActor
    func navigateRejectsLMS() async {
        let tool = NavigateToPageTool()
        do {
            _ = try await tool.execute(
                arguments: ["page": .string("brightspace")],
                context: AssistantTestFixtures.toolContext(page: .calendar)
            )
            Issue.record("Expected LMS rejection")
        } catch {
            #expect(error.localizedDescription.localizedCaseInsensitiveContains("learning management"))
        }
    }

    @Test("Update setting rejects protected web search key")
    @MainActor
    func updateSettingRejectsProtectedKey() async {
        let tool = UpdateAppSettingTool()
        do {
            _ = try await tool.execute(
                arguments: [
                    "key": .string(AssistantWebSearchSettings.customBaseURLKey),
                    "value": .string("https://evil.example")
                ],
                context: AssistantTestFixtures.toolContext()
            )
            Issue.record("Expected rejection")
        } catch {
            #expect(!error.localizedDescription.isEmpty)
        }
    }

    @Test("Registry contains core degree and planning tools")
    @MainActor
    func registryContainsCoreTools() {
        let names = Set(AIAssistantToolRegistry.all.map(\.descriptor.name))
        let required = [
            "explainRequirements",
            "getDegreeAudit",
            "draftSemesterPlan",
            "getStudentLearningProfile",
            "assessRequirementRisk",
            "semanticCatalogSearch",
            "getAidDeadlines",
            "assessRegistrationReadiness",
            "simulateCourseSwap",
            "suggestCoursesForSkillGaps",
            "assessRegistrationWorkload",
            "proposeSyllabusDeadlineSync",
            "searxWebSearch",
            "getUpcomingSchedule",
            "getStudentProfile"
        ]
        for name in required {
            #expect(names.contains(name), "Missing tool: \(name)")
        }
    }
}
