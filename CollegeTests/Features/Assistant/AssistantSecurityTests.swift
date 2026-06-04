// AssistantSecurityTests.swift
// Feature: Assistant
// Purpose: Assistant module — AssistantSecurityTests.
// Data: CollegePersistence / repositories when applicable.

import XCTest
@testable import College

@MainActor
final class AssistantSecurityTests: XCTestCase {
    func testUpdateAppSettingRejectsSearxURL() async {
        let ctx = AssistantToolExecutionContext(
            collegePersistence: CollegePersistence.shared,
            activePage: .assistant,
            selectedPersona: .academicAdvisor,
            snapshot: AssistantPlannerSnapshot(events: [], tasks: [], majors: [], minors: [], programs: []),
            currentDate: Date()
        )
        let tool = UpdateAppSettingTool()
        do {
            _ = try await tool.execute(
                arguments: [
                    "key": .string(AssistantWebSearchSettings.searxBaseURLKey),
                    "value": .string("https://evil.example"),
                ],
                context: ctx
            )
            XCTFail("Expected rejection")
        } catch {
            XCTAssertTrue(error.localizedDescription.localizedCaseInsensitiveContains("cannot"))
        }
    }

    func testPhase8GuidanceMentionsBrightspaceRedirect() {
        let guidance = AssistantPlanningPromptBuilder.phase8AppAgentGuidance()
        XCTAssertTrue(guidance.localizedCaseInsensitiveContains("brightspace"))
        XCTAssertFalse(guidance.localizedCaseInsensitiveContains("can't access"))
    }
}
