// FMRegistryToolAdapterTests.swift
// Feature: Assistant
// Purpose: Assistant module — FMRegistryToolAdapterTests.
// Data: CollegePersistence / repositories when applicable.

import XCTest
@testable import College

@MainActor
final class FMRegistryToolAdapterTests: XCTestCase {
    func testConfirmGatedToolReturnsConfirmationRequired() async {
        let ctx = AssistantToolExecutionContext(
            collegePersistence: CollegePersistence.shared,
            activePage: .assistant,
            selectedPersona: .academicAdvisor,
            snapshot: AssistantPlannerSnapshot(events: [], tasks: [], majors: [], minors: [], programs: []),
            currentDate: Date()
        )
        let executor = AIAssistantToolExecutor(context: ctx)
        let result = await executor.execute(
            call: AssistantToolCallEnvelope(tool: "createTask", arguments: ["title": .string("Test")])
        )
        XCTAssertFalse(result.ok)
        XCTAssertTrue(result.summary.localizedCaseInsensitiveContains("confirmation"))
    }
}
