// AIAssistantSettingsTools.swift
// Feature: Assistant
// Purpose: Assistant module — GetAppSettingTool.
// Data: CollegePersistence / repositories when applicable.

import Foundation

@MainActor
struct GetAppSettingTool: AIAssistantTool {
    let descriptor = AssistantToolDescriptor(
        name: "getAppSetting",
        description: "Read a whitelisted app setting value for explanations.",
        allowedPersonas: [.academicAdvisor, .financialAdvisor],
        mode: .read,
        requiresConfirmation: false,
        confirmationStyle: AssistantConfirmationStyle.none,
        inputSchemaDescription: "{\"key\":\"string\"}",
        outputSchemaDescription: "key, value, label",
        sourceLabel: "UserDefaults"
    )

    func execute(
        arguments: [String: AssistantJSONValue],
        context: AssistantToolExecutionContext
    ) async throws -> AssistantToolResultEnvelope {
        guard let key = arguments["key"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !key.isEmpty else {
            throw AssistantToolExecutionError.invalidArguments("key is required")
        }
        guard AssistantSettingsKey.isReadable(key: key) else {
            throw AssistantToolExecutionError.invalidArguments("That key cannot be read via the assistant.")
        }
        let value = UserDefaults.standard.object(forKey: key).map { String(describing: $0) } ?? ""
        let label = AssistantSettingsKey(rawValue: key)?.displayLabel ?? key
        return AssistantToolResultEnvelope(
            tool: descriptor.name,
            ok: true,
            result: ["key": .string(key), "value": .string(value), "label": .string(label)],
            source: descriptor.sourceLabel,
            summary: "\(label) is currently \(value.isEmpty ? "unset" : value).",
            errorMessage: nil
        )
    }
}

@MainActor
struct UpdateAppSettingTool: AIAssistantTool {
    private struct Arguments: Decodable {
        let key: String
        let value: String
    }

    let descriptor = AssistantToolDescriptor(
        name: "updateAppSetting",
        description: "Prepare a whitelisted preference change for confirmation (response length, streaming, semantic catalog, appearance).",
        allowedPersonas: [.academicAdvisor, .financialAdvisor],
        mode: .write,
        requiresConfirmation: true,
        confirmationStyle: .card,
        inputSchemaDescription: "{\"key\":\"string\",\"value\":\"string\"}",
        outputSchemaDescription: "key, value, label, previousValue",
        sourceLabel: "UserDefaults"
    )

    func execute(
        arguments: [String: AssistantJSONValue],
        context: AssistantToolExecutionContext
    ) async throws -> AssistantToolResultEnvelope {
        let decoded = try AssistantJSONValue.decodeObject(Arguments.self, from: arguments)
        let key = decoded.key.trimmingCharacters(in: .whitespacesAndNewlines)
        if let reason = AssistantSettingsKey.rejectedWriteReason(for: key) {
            throw AssistantToolExecutionError.invalidArguments(reason)
        }
        guard AssistantSettingsKey.isWritable(key: key) else {
            throw AssistantToolExecutionError.invalidArguments("That setting cannot be changed via the assistant.")
        }
        let previous = UserDefaults.standard.object(forKey: key).map { String(describing: $0) } ?? ""
        let label = AssistantSettingsKey(rawValue: key)?.displayLabel ?? key
        let payload: [String: AssistantJSONValue] = [
            "key": .string(key),
            "value": .string(decoded.value),
            "label": .string(label),
            "previousValue": .string(previous),
        ]
        return AssistantToolResultEnvelope(
            tool: descriptor.name,
            ok: true,
            result: payload,
            source: descriptor.sourceLabel,
            summary: "Prepared change to \(label).",
            errorMessage: nil
        )
    }
}
