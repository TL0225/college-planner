// AssistantPlanJSONParser.swift
// Feature: Assistant
// Purpose: Assistant module — AssistantJSONRobustnessSettings.
// Data: CollegePersistence / repositories when applicable.

import Foundation

// MARK: - Settings (UserDefaults)

enum AssistantJSONRobustnessSettings {
    static let repairEnabledKey = "assistant.json.repair.enabled"
    /// Second model call on decode failure; tolerant parsing stays on regardless.
    static var isRepairGenerationEnabled: Bool {
        UserDefaults.standard.object(forKey: repairEnabledKey) != nil
            ? UserDefaults.standard.bool(forKey: repairEnabledKey)
            : true
    }

    static let repairPromptExcerptMaxCharacters = 4096
    static let maxRawCharactersForJSONParse = 512_000
}

// MARK: - Parser

/// Tolerant extraction of planner / reply JSON before strict ``JSONDecoder`` paths.
enum AssistantPlanJSONParser {

    static func boundedRawString(_ raw: String) -> String {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.count <= AssistantJSONRobustnessSettings.maxRawCharactersForJSONParse { return t }
        return String(t.suffix(AssistantJSONRobustnessSettings.maxRawCharactersForJSONParse))
    }

    static func repairExcerpt(from raw: String, limit: Int = AssistantJSONRobustnessSettings.repairPromptExcerptMaxCharacters) -> String {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.count <= limit { return t }
        return String(t.suffix(limit))
    }

    /// Extracts normalized final reply text from model output.
    static func parseReply(from raw: String) -> String? {
        let bounded = boundedRawString(raw)
        let jsonString = JSONSanitizer.extractJSONPayload(from: bounded) ?? bounded
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            return nil
        }
        guard let dict = json as? [String: Any] else { return nil }

        let keys = ["reply", "message", "answer", "response", "text"]
        for key in keys {
            if let s = stringValue(forReply: dict[key]) { return s }
        }
        return nil
    }

    /// Extracts a planning action; optionally rejects tool names not in the planning catalog.
    static func parseAction(from raw: String, allowedToolNames: Set<String>? = nil) -> AssistantModelAction? {
        let bounded = boundedRawString(raw)
        let jsonString = JSONSanitizer.extractJSONPayload(from: bounded) ?? bounded
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            return nil
        }
        guard let dict = json as? [String: Any] else { return nil }

        var rawAction = normalizedActionString(dict["action"])
        if rawAction == "finalanswer" { rawAction = "final_answer" }
        if rawAction == "toolcall" { rawAction = "tool_call" }

        let toolName = toolName(from: dict)
        if rawAction == nil, toolName != nil {
            rawAction = "tool_call"
        }

        if rawAction == "final_answer" {
            if let reply = finalAnswerText(from: dict) {
                return .finalAnswer(reply)
            }
            return nil
        }

        if rawAction == "tool_call" {
            guard let name = toolName, !name.isEmpty else { return nil }
            if let allowed = allowedToolNames, !allowed.contains(name) {
                return nil
            }
            let argsDict = coerceArgumentsDictionary(dict["arguments"] ?? dict["args"]) ?? [:]
            let safeArgsData = (try? JSONSerialization.data(withJSONObject: argsDict)) ?? Data()
            let safeArgs = (try? JSONDecoder().decode([String: AssistantJSONValue].self, from: safeArgsData)) ?? [:]
            return .toolCall(AssistantToolCallEnvelope(tool: name, arguments: safeArgs))
        }

        if rawAction == nil, toolName == nil {
            if let reply = finalAnswerText(from: dict) {
                return .finalAnswer(reply)
            }
        }

        return nil
    }

    // MARK: - Internals

    private static func normalizedActionString(_ value: Any?) -> String? {
        guard let s = value as? String else { return nil }
        let t = s.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    private static func toolName(from dict: [String: Any]) -> String? {
        let keys = ["tool", "tool_name", "toolName"]
        for key in keys {
            if let s = dict[key] as? String {
                let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty { return t }
            }
        }
        return nil
    }

    private static func finalAnswerText(from dict: [String: Any]) -> String? {
        let keys = ["reply", "message", "answer", "response", "text"]
        for key in keys {
            if let s = stringValue(forReply: dict[key]) { return s }
        }
        return nil
    }

    private static func stringValue(forReply json: Any?) -> String? {
        switch json {
        case let s as String:
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        case let n as NSNumber:
            let t = n.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        case let b as Bool:
            return b ? "true" : "false"
        default:
            return nil
        }
    }

    private static func coerceArgumentsDictionary(_ any: Any?) -> [String: Any]? {
        if let d = any as? [String: Any] { return d }
        if let s = any as? String {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty, let data = t.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) else { return nil }
            return obj as? [String: Any]
        }
        return nil
    }
}
