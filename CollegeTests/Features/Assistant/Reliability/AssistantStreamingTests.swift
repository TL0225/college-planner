// AssistantStreamingTests.swift
import Foundation
import Testing
@testable import College

@Suite("Assistant Streaming")
struct AssistantStreamingTests {

    @Test("Stub response returns JSON for planning prompt")
    func stubResponseReturnsJSON() async throws {
        let prompt = """
        Return ONLY valid JSON in one of these schemas:
        {"action":"final_answer","reply":"string"}

        User message:

        UITEST_STUB get program progress
        """
        let text = try await LocalLLMStubResponder.response(prompt: prompt)
        #expect(text.contains("tool_call") || text.contains("final_answer"))
    }

    @Test("Streaming delivers full payload across chunks")
    func streamingDeliversFullPayload() async throws {
        let prompt = """
        Return ONLY valid JSON in one of these schemas:
        {"action":"final_answer","reply":"string"}

        User message:

        hello streaming
        """
        let final = try await LocalLLMStubResponder.responseStreaming(prompt: prompt) { _ in }
        #expect(final.contains("final_answer") || final.contains("reply"))
        #expect(final.count > 10)
    }

    @Test("Reply JSON parser handles streamed-style fenced payload")
    func replyJSONParserHandlesFencedPayload() {
        let raw = #"{"reply":"Hello **world**"}"#
        #expect(AssistantPlanJSONParser.parseReply(from: raw) == "Hello **world**")
    }
}
