// FMRegistryToolAdapterTests.swift
import Foundation
import Testing
@testable import College

@Suite("FM Registry Tool Adapter")
struct FMRegistryToolAdapterTests {

    @Test("Confirm gated tool returns confirmation required")
    @MainActor
    func confirmGatedToolReturnsConfirmationRequired() async {
        let ctx = AssistantTestFixtures.toolContext()
        let executor = AIAssistantToolExecutor(context: ctx)
        let result = await executor.execute(
            call: AssistantToolCallEnvelope(tool: "createTask", arguments: ["title": .string("Test")])
        )
        #expect(!result.ok)
        #expect(result.summary.localizedCaseInsensitiveContains("confirmation"))
    }
}
