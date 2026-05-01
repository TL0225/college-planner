import XCTest
@testable import College

final class AssistantPlanJSONParserTests: XCTestCase {

    func testParseReplyAcceptsFencesAndMessageAlias() {
        let raw = """
        Here you go:
        ```json
        {"message": "Hello from alias."}
        ```
        """
        XCTAssertEqual(AssistantPlanJSONParser.parseReply(from: raw), "Hello from alias.")
    }

    func testParseReplyExtraKeys() {
        let raw = #"{"reply":"ok","tool":"ignored","note":"x"}"#
        XCTAssertEqual(AssistantPlanJSONParser.parseReply(from: raw), "ok")
    }

    func testParseReplyEmptyObjectReturnsNil() {
        XCTAssertNil(AssistantPlanJSONParser.parseReply(from: "{}"))
    }

    func testParseActionToolNameWithoutAction() {
        let raw = #"{"toolName": "getStudentProfile", "arguments": {}}"#
        let allowed: Set<String> = ["getStudentProfile"]
        guard case .toolCall(let env)? = AssistantPlanJSONParser.parseAction(from: raw, allowedToolNames: allowed) else {
            return XCTFail("expected tool call")
        }
        XCTAssertEqual(env.tool, "getStudentProfile")
        XCTAssertTrue(env.arguments.isEmpty)
    }

    func testParseActionFinalAnswerCaseInsensitive() {
        let raw = #"{"action": "FinalAnswer", "reply": "Done."}"#
        guard case .finalAnswer(let text)? = AssistantPlanJSONParser.parseAction(from: raw, allowedToolNames: []) else {
            return XCTFail("expected final answer")
        }
        XCTAssertEqual(text, "Done.")
    }

    func testParseActionRejectsUnknownToolWhenAllowlisted() {
        let raw = #"{"action":"tool_call","tool":"fakeTool","arguments":{}}"#
        XCTAssertNil(AssistantPlanJSONParser.parseAction(from: raw, allowedToolNames: ["getStudentProfile"]))
    }

    func testParseActionArgumentsAsJSONString() {
        let raw = #"""
        {"action":"tool_call","tool":"getStudentProfile","arguments":"{\"compact\":true}"}
        """#
        let allowed: Set<String> = ["getStudentProfile"]
        guard case .toolCall(let env)? = AssistantPlanJSONParser.parseAction(from: raw, allowedToolNames: allowed) else {
            return XCTFail("expected tool call")
        }
        XCTAssertEqual(env.arguments["compact"]?.boolValue, true)
    }

    func testBoundedRawStringTruncatesExtremelyLongInput() {
        let huge = String(repeating: "a", count: AssistantJSONRobustnessSettings.maxRawCharactersForJSONParse + 50)
        let bounded = AssistantPlanJSONParser.boundedRawString(huge)
        XCTAssertEqual(bounded.count, AssistantJSONRobustnessSettings.maxRawCharactersForJSONParse)
    }
}
