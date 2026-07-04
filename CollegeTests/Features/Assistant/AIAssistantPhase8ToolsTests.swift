// AIAssistantPhase8ToolsTests.swift
// Phase 8 tool registry (Swift Testing).

import Foundation
import Testing
@testable import College

@Suite("AI Assistant Phase 8 Tools")
struct AIAssistantPhase8ToolsTests {

    @Test("Registry has phase 8 tools")
    @MainActor
    func registryHasPhase8Tools() {
        let names = Set(AIAssistantToolRegistry.all.map { $0.descriptor.name })
        #expect(names.contains("navigateToPage"))
        #expect(names.contains("resolveEventLocation"))
        #expect(names.contains("searchDocuments"))
        #expect(names.contains("addCourseToPlan"))
        #expect(names.count >= 40)
    }

    @Test("Planning catalog JSON is non-empty for advisor")
    @MainActor
    func planningCatalogJSONIsNonEmptyForAdvisor() {
        let json = AIAssistantToolRegistry.planningCatalogJSON(for: .academicAdvisor)
        #expect(json.count > 400)
        #expect(json.contains("getStudentProfile"))
        #expect(json.contains("navigateToPage"))
    }

    @Test("Navigate tool rejects Brightspace")
    @MainActor
    func navigateToolRejectsBrightspace() async {
        let ctx = AssistantTestFixtures.toolContext(page: .calendar)
        let tool = NavigateToPageTool()
        do {
            _ = try await tool.execute(
                arguments: ["page": .string("brightspace")],
                context: ctx
            )
            Issue.record("Expected brightspace rejection")
        } catch {
            #expect(error.localizedDescription.localizedCaseInsensitiveContains("learning management"))
        }
    }
}
