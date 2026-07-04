// FoundationModelsAssistantSession.swift
// Feature: Assistant
// Purpose: Assistant module — FoundationModelsAssistantSession.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import FoundationModels

@MainActor
final class FoundationModelsAssistantSession: AssistantInferenceSession {
    /// Registering dozens of tools at once has destabilized `LanguageModelSession` on macOS 26.
    private static let maxRegisteredTools = 16

    private let makeExecutor: () -> AIAssistantToolExecutor

    init(makeExecutor: @escaping @MainActor @Sendable () -> AIAssistantToolExecutor) {
        self.makeExecutor = makeExecutor
    }

    nonisolated func plan(request: AssistantPlanningRequest) async -> AssistantPlanningResult {
        await planOnMainActor(request: request)
    }

    @MainActor
    private func planOnMainActor(request: AssistantPlanningRequest) async -> AssistantPlanningResult {
        let allowed = request.toolDescriptors.filter { request.allowedToolNames.contains($0.name) }
        let cappedDescriptors = Self.foundationModelsToolDescriptors(from: allowed)
        let provider = makeExecutor
        let tools: [any Tool] = cappedDescriptors.map { descriptor in
            FMRegistryToolAdapter(descriptor: descriptor, makeExecutor: { @MainActor @Sendable in provider() })
        }
        let instructions = AssistantPlanningPromptBuilder.foundationModelsInstructions(
            role: request.role,
            allowedToolNames: request.allowedToolNames
        )
        let userPrompt = AssistantPlanningPromptBuilder.foundationModelsUserPrompt(request: request)

        do {
            let session = LanguageModelSession(
                tools: tools,
                instructions: instructions
            )
            let response = try await session.respond(to: userPrompt)

            if let pending = Self.pendingConfirmationToolCall(in: session.transcript, allowed: request.allowedToolNames) {
                return AssistantPlanningResult(
                    action: .toolCall(pending),
                    fallbackReply: nil,
                    failureReason: nil,
                    diagnostics: "fm_confirm_tool",
                    backend: .foundationModels
                )
            }

            let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                return AssistantPlanningResult(
                    action: nil,
                    fallbackReply: nil,
                    failureReason: .decodeFailed,
                    diagnostics: "fm_empty_response",
                    backend: .foundationModels
                )
            }
            return AssistantPlanningResult(
                action: .finalAnswer(text),
                fallbackReply: nil,
                failureReason: nil,
                diagnostics: nil,
                backend: .foundationModels
            )
        } catch {
            return AssistantPlanningResult(
                action: nil,
                fallbackReply: nil,
                failureReason: .generationFailed,
                diagnostics: error.localizedDescription,
                backend: .foundationModels
            )
        }
    }

    /// Prefer read tools and cap count so Foundation Models session creation stays stable.
    private static func foundationModelsToolDescriptors(
        from descriptors: [AssistantToolDescriptor]
    ) -> [AssistantToolDescriptor] {
        let sorted = descriptors.sorted { lhs, rhs in
            if lhs.requiresConfirmation != rhs.requiresConfirmation {
                return !lhs.requiresConfirmation
            }
            return lhs.name < rhs.name
        }
        return Array(sorted.prefix(maxRegisteredTools))
    }

    private static func pendingConfirmationToolCall(
        in transcript: Transcript,
        allowed: Set<String>
    ) -> AssistantToolCallEnvelope? {
        for entry in transcript.reversed() {
            guard case .toolCalls(let calls) = entry else { continue }
            for call in calls {
                guard allowed.contains(call.toolName) else { continue }
                guard let descriptor = AIAssistantToolRegistry.descriptor(named: call.toolName),
                      descriptor.requiresConfirmation else { continue }
                let args = (try? AssistantJSONValue.decodeArguments(from: call.arguments)) ?? [:]
                return AssistantToolCallEnvelope(tool: call.toolName, arguments: args)
            }
        }
        return nil
    }
}
