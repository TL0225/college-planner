// LocalLLMStubResponder.swift
// Feature: SyllabusAI
// Purpose: SyllabusAI module — LocalLLMStubResponder.
// Data: CollegePersistence / repositories when applicable.

import Foundation

/// Deterministic MLX bypass for UI tests (`--uitest-local-llm-stub` + `--ui-test-boot-main`).
enum LocalLLMStubResponder {
    private static let replySchemaMarker = #"{"reply":"string"}"#
    private static let planningSchemaMarker = "Return ONLY valid JSON in one of these schemas:"

    static func shouldHandle() -> Bool {
        UITestLaunchFlags.localLLMStubEnabled
    }

    /// Returns full JSON string; optionally streams the same string in chunks for streaming APIs.
    static func response(prompt: String) async throws -> String {
        if isNarrowReplyPrompt(prompt) {
            return replyJSON(for: prompt)
        }
        if prompt.contains(planningSchemaMarker) {
            return planningJSON(for: prompt)
        }
        return """
        {"reply":"Stub: unclassified prompt shape."}
        """
    }

    static func responseStreaming(
        prompt: String,
        onChunk: @escaping @Sendable (String) async -> Void
    ) async throws -> String {
        let text = try await response(prompt: prompt)
        let chunkSize = 48
        var idx = text.startIndex
        while idx < text.endIndex {
            let end = text.index(idx, offsetBy: chunkSize, limitedBy: text.endIndex) ?? text.endIndex
            let piece = String(text[idx..<end])
            await onChunk(piece)
            idx = end
        }
        return text
    }

    private static func isNarrowReplyPrompt(_ prompt: String) -> Bool {
        prompt.contains(replySchemaMarker) && !prompt.contains(planningSchemaMarker)
    }

    private static func extractUserMessage(from prompt: String) -> String {
        let marker = "\nUser message:\n\n"
        guard let range = prompt.range(of: marker, options: .backwards) else {
            return prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return String(prompt[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func hasPriorToolResults(_ prompt: String) -> Bool {
        prompt.contains("Prior tool results this turn")
    }

    private static func replyJSON(for prompt: String) -> String {
        let msg = extractUserMessage(from: prompt)
        if msg.contains("UITEST_STUB malformed") {
            return "not json"
        }
        let body = "Stub final reply for: \(msg.prefix(120))"
        return #"{"reply":"\#(escapeJSON(body))"}"#
    }

    private static func planningJSON(for prompt: String) -> String {
        if hasPriorToolResults(prompt) {
            let summary = """
            Stub summary: tool results are in your context. Programs show remaining credits; follow your advisor for official rules.
            """
            return #"{"action":"final_answer","reply":"\#(escapeJSON(summary))"}"#
        }

        let msg = extractUserMessage(from: prompt)

        if msg.localizedCaseInsensitiveContains("UITEST_CONFIRM create task") {
            return #"""
            {"action":"tool_call","tool":"createTask","arguments":{"title":"UITest Seeded Task","dueDateISO8601":null}}
            """#
        }

        if msg.localizedCaseInsensitiveContains("UITEST_STUB get program progress") {
            return #"""
            {"action":"tool_call","tool":"getProgramProgress","arguments":{}}
            """#
        }

        if msg.localizedCaseInsensitiveContains("UITEST_STUB decode salvage") {
            return "```json\n{\"action\":\"final_answer\",\"reply\":\"Salvaged from fences\"}\n```"
        }

        let fallback = "Stub planner: use UITEST_STUB get program progress or UITEST_CONFIRM create task for scripted flows."
        return #"{"action":"final_answer","reply":"\#(escapeJSON(fallback))"}"#
    }

    private static func escapeJSON(_ s: String) -> String {
        s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
}
