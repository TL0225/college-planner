// FMRegistryToolAdapter.swift
// Feature: Assistant
// Purpose: Assistant module — FMRegistryToolAdapter.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import FoundationModels

extension AssistantJSONValue {
    init(fmJSONObject content: GeneratedContent) throws {
        guard let data = content.jsonString.data(using: .utf8) else {
            throw AssistantToolExecutionError.invalidArguments("Invalid tool arguments encoding")
        }
        self = try JSONDecoder().decode(AssistantJSONValue.self, from: data)
    }

    static func decodeArguments(from content: GeneratedContent) throws -> [String: AssistantJSONValue] {
        let root = try AssistantJSONValue(fmJSONObject: content)
        if case .object(let object) = root {
            return object
        }
        return [:]
    }
}

struct FMRegistryToolAdapter: Tool {
    typealias Arguments = GeneratedContent
    typealias Output = String

    let descriptor: AssistantToolDescriptor
    private let makeExecutor: @MainActor @Sendable () -> AIAssistantToolExecutor

    init(
        descriptor: AssistantToolDescriptor,
        makeExecutor: @escaping @MainActor @Sendable () -> AIAssistantToolExecutor
    ) {
        self.descriptor = descriptor
        self.makeExecutor = makeExecutor
    }

    var name: String { descriptor.name }

    var description: String {
        descriptor.description + "\n" + descriptor.inputSchemaDescription
    }

    nonisolated func call(arguments: GeneratedContent) async throws -> String {
        try await callOnMainActor(arguments: arguments)
    }

    @MainActor
    private func callOnMainActor(arguments: GeneratedContent) async throws -> String {
        let decodedArgs = try AssistantJSONValue.decodeArguments(from: arguments)
        let call = AssistantToolCallEnvelope(tool: descriptor.name, arguments: decodedArgs)

        if descriptor.requiresConfirmation {
            let envelope = AssistantToolResultEnvelope(
                tool: descriptor.name,
                ok: false,
                result: nil,
                source: "assistant.tooling",
                summary: AssistantToolExecutionError.confirmationRequired(descriptor.name).localizedDescription,
                errorMessage: AssistantToolExecutionError.confirmationRequired(descriptor.name).localizedDescription
            )
            return try Self.encodeEnvelope(envelope)
        }

        let executor = makeExecutor()
        let envelope = await executor.execute(call: call)
        return try Self.encodeEnvelope(envelope)
    }

    static func encodeEnvelope(_ envelope: AssistantToolResultEnvelope) throws -> String {
        let data = try JSONEncoder().encode(envelope)
        guard let raw = String(data: data, encoding: .utf8) else {
            throw AssistantToolExecutionError.invalidArguments("Could not encode tool result")
        }
        return raw
    }
}
