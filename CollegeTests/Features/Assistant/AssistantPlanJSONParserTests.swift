// AssistantPlanJSONParserTests.swift
import Foundation
import Testing
@testable import College

@Suite("Assistant Plan JSON Parser")
struct AssistantPlanJSONParserTests {

    @Test("Parse reply accepts fences and message alias")
    func parseReplyAcceptsFencesAndMessageAlias() {
        let raw = """
        Here you go:
        ```json
        {"message": "Hello from alias."}
        ```
        """
        #expect(AssistantPlanJSONParser.parseReply(from: raw) == "Hello from alias.")
    }

    @Test("Parse reply extra keys")
    func parseReplyExtraKeys() {
        let raw = #"{"reply":"ok","tool":"ignored","note":"x"}"#
        #expect(AssistantPlanJSONParser.parseReply(from: raw) == "ok")
    }

    @Test("Parse reply empty object returns nil")
    func parseReplyEmptyObjectReturnsNil() {
        #expect(AssistantPlanJSONParser.parseReply(from: "{}") == nil)
    }

    @Test("Parse action tool name without action")
    func parseActionToolNameWithoutAction() {
        let raw = #"{"toolName": "getStudentProfile", "arguments": {}}"#
        let allowed: Set<String> = ["getStudentProfile"]
        guard case .toolCall(let env)? = AssistantPlanJSONParser.parseAction(from: raw, allowedToolNames: allowed) else {
            Issue.record("expected tool call")
            return
        }
        #expect(env.tool == "getStudentProfile")
        #expect(env.arguments.isEmpty)
    }

    @Test("Parse action final answer case insensitive")
    func parseActionFinalAnswerCaseInsensitive() {
        let raw = #"{"action": "FinalAnswer", "reply": "Done."}"#
        guard case .finalAnswer(let text)? = AssistantPlanJSONParser.parseAction(from: raw, allowedToolNames: []) else {
            Issue.record("expected final answer")
            return
        }
        #expect(text == "Done.")
    }

    @Test("Parse action rejects unknown tool when allowlisted")
    func parseActionRejectsUnknownToolWhenAllowlisted() {
        let raw = #"{"action":"tool_call","tool":"fakeTool","arguments":{}}"#
        #expect(AssistantPlanJSONParser.parseAction(from: raw, allowedToolNames: ["getStudentProfile"]) == nil)
    }

    @Test("Parse action arguments as JSON string")
    func parseActionArgumentsAsJSONString() {
        let raw = #"""
        {"action":"tool_call","tool":"getStudentProfile","arguments":"{\"compact\":true}"}
        """#
        let allowed: Set<String> = ["getStudentProfile"]
        guard case .toolCall(let env)? = AssistantPlanJSONParser.parseAction(from: raw, allowedToolNames: allowed) else {
            Issue.record("expected tool call")
            return
        }
        #expect(env.arguments["compact"]?.boolValue == true)
    }

    @Test("Bounded raw string truncates extremely long input")
    func boundedRawStringTruncatesExtremelyLongInput() {
        let huge = String(repeating: "a", count: AssistantJSONRobustnessSettings.maxRawCharactersForJSONParse + 50)
        let bounded = AssistantPlanJSONParser.boundedRawString(huge)
        #expect(bounded.count == AssistantJSONRobustnessSettings.maxRawCharactersForJSONParse)
    }
}
