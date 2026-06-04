// ToolCallStreamParser.swift
// Feature: Assistant
// Purpose: Assistant module — ToolCallStreamParseResult.
// Data: CollegePersistence / repositories when applicable.

import Foundation

struct ToolCallStreamParseResult {
    let action: AssistantModelAction?
    let extractedJSON: String?
}

/// Incrementally scans streamed model text and emits the earliest valid action envelope.
struct ToolCallStreamParser {
    private(set) var buffer: String = ""
    private(set) var hasEmittedAction = false

    mutating func append(_ chunk: String) -> ToolCallStreamParseResult {
        guard !chunk.isEmpty else {
            return ToolCallStreamParseResult(action: nil, extractedJSON: nil)
        }
        buffer.append(chunk)
        guard !hasEmittedAction else {
            return ToolCallStreamParseResult(action: nil, extractedJSON: nil)
        }
        guard let candidate = JSONSanitizer.extractJSONPayload(from: buffer) else {
            return ToolCallStreamParseResult(action: nil, extractedJSON: nil)
        }
        let action: AssistantModelAction?
        if let tolerant = AssistantPlanJSONParser.parseAction(from: candidate, allowedToolNames: nil) {
            action = tolerant
        } else if let data = candidate.data(using: .utf8),
                  let envelope = try? JSONDecoder().decode(AssistantActionEnvelope.self, from: data) {
            action = envelope.toModelAction()
        } else {
            action = nil
        }
        if action != nil {
            hasEmittedAction = true
        }
        return ToolCallStreamParseResult(action: action, extractedJSON: candidate)
    }
}

struct AssistantActionEnvelope: Codable {
    let action: String
    let reply: String?
    let tool: String?
    let arguments: [String: AssistantJSONValue]?

    func toModelAction() -> AssistantModelAction? {
        switch action {
        case "final_answer":
            guard let reply = reply?.trimmingCharacters(in: .whitespacesAndNewlines), !reply.isEmpty else {
                return nil
            }
            return .finalAnswer(reply)
        case "tool_call":
            guard let tool = tool?.trimmingCharacters(in: .whitespacesAndNewlines), !tool.isEmpty else {
                return nil
            }
            return .toolCall(AssistantToolCallEnvelope(tool: tool, arguments: arguments ?? [:]))
        default:
            return nil
        }
    }
}
