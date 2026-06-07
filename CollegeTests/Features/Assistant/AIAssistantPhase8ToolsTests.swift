// AIAssistantPhase8ToolsTests.swift
// Feature: Assistant
// Purpose: Assistant module — AIAssistantPhase8ToolsTests.
// Data: CollegePersistence / repositories when applicable.

import XCTest
@testable import College

@MainActor
final class AIAssistantPhase8ToolsTests: XCTestCase {
    func testRegistryHasPhase8Tools() {
        let names = Set(AIAssistantToolRegistry.all.map { $0.descriptor.name })
        XCTAssertTrue(names.contains("navigateToPage"))
        XCTAssertTrue(names.contains("resolveEventLocation"))
        XCTAssertTrue(names.contains("searchDocuments"))
        XCTAssertTrue(names.contains("addCourseToPlan"))
        XCTAssertGreaterThanOrEqual(names.count, 40)
    }

    func testPlanningCatalogJSONIsNonEmptyForAdvisor() {
        let json = AIAssistantToolRegistry.planningCatalogJSON(for: .academicAdvisor)
        XCTAssertGreaterThan(json.count, 400)
        XCTAssertTrue(json.contains("getStudentProfile"))
        XCTAssertTrue(json.contains("navigateToPage"))
    }

    func testNavigateToolRejectsBrightspace() async throws {
        let ctx = AssistantToolExecutionContext(
            collegePersistence: CollegePersistence.shared,
            activePage: .calendar,
            selectedPersona: .academicAdvisor,
            snapshot: AssistantPlannerSnapshot(events: [], tasks: [], majors: [], minors: [], programs: []),
            currentDate: Date()
        )
        let tool = NavigateToPageTool()
        do {
            _ = try await tool.execute(
                arguments: ["page": .string("brightspace")],
                context: ctx
            )
            XCTFail("Expected brightspace rejection")
        } catch {
            XCTAssertTrue(error.localizedDescription.localizedCaseInsensitiveContains("brightspace"))
        }
    }
}
