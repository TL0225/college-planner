// LocalLLMRunner.swift
// Feature: SyllabusAI
// Purpose: SyllabusAI module — LocalLLMRunnerError.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import MLXLLM
import MLXLMCommon

enum LocalLLMRunnerError: LocalizedError {
    case unavailable(String)
    case generationFailed

    var errorDescription: String? {
        switch self {
        case .unavailable(let msg):
            return msg
        case .generationFailed:
            return "Local model failed to generate a response."
        }
    }
}

/// Actor isolation ensures MLX work never blocks the main thread.
///
/// All inference and weight loads run through ``MLXTaskQueue`` so Qwen JSON work
/// never races catalog embedders on the same GPU.
actor LocalLLMRunner {
    static let shared = LocalLLMRunner()

    private var cachedModelDirectory: URL?
    private var cachedContainer: ModelContainer?

    // MARK: - Inference

    /// Single integration point for on-device JSON LLM inference (Qwen via MLXLLM).
    func generateJSON(prompt: String, modelPath: URL, maxTokens: Int = 700) async throws -> String {
        if LocalLLMStubResponder.shouldHandle() {
            return try await LocalLLMStubResponder.response(prompt: prompt)
        }
        try requireSupportedMetalDevice()
        await MainActor.run { LLMMemoryLifecycle.shared.cancelIdleRelease() }
        let output = try await MLXTaskQueue.shared.run(priority: .userInitiated) {
            try await self.generateJSONUnqueued(prompt: prompt, modelPath: modelPath, maxTokens: maxTokens)
        }
        await MainActor.run { LLMMemoryLifecycle.shared.touch() }
        return output
    }

    /// Streaming variant for on-device JSON generation.
    func generateJSONStreaming(
        prompt: String,
        modelPath: URL,
        maxTokens: Int = 700,
        onChunk: @escaping @Sendable (String) async -> Void
    ) async throws -> String {
        if LocalLLMStubResponder.shouldHandle() {
            return try await LocalLLMStubResponder.responseStreaming(prompt: prompt, onChunk: onChunk)
        }
        try requireSupportedMetalDevice()
        await MainActor.run { LLMMemoryLifecycle.shared.cancelIdleRelease() }
        let output = try await MLXTaskQueue.shared.run(priority: .userInitiated) {
            try await self.generateJSONStreamingUnqueued(
                prompt: prompt,
                modelPath: modelPath,
                maxTokens: maxTokens,
                onChunk: onChunk
            )
        }
        await MainActor.run { LLMMemoryLifecycle.shared.touch() }
        return output
    }

    private func generateJSONUnqueued(prompt: String, modelPath: URL, maxTokens: Int) async throws -> String {
        let container = try await resolvedContainer(modelPath: modelPath)

        let jsonOnlyInstructions =
            "You are a careful parser. Return ONLY valid JSON. No markdown, no code fences, no extra commentary."

        let parameters = GenerateParameters(
            maxTokens: maxTokens,
            temperature: 0.2,
            topP: 0.95,
            repetitionPenalty: 1.05,
            repetitionContextSize: 64
        )

        let session = ChatSession(
            container,
            instructions: jsonOnlyInstructions,
            generateParameters: parameters
        )

        let output = try await session.respond(to: prompt)
        if output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw LocalLLMRunnerError.generationFailed
        }
        return output
    }

    private func generateJSONStreamingUnqueued(
        prompt: String,
        modelPath: URL,
        maxTokens: Int,
        onChunk: @escaping @Sendable (String) async -> Void
    ) async throws -> String {
        let container = try await resolvedContainer(modelPath: modelPath)

        let jsonOnlyInstructions =
            "You are a careful parser. Return ONLY valid JSON. No markdown, no code fences, no extra commentary."
        let parameters = GenerateParameters(
            maxTokens: maxTokens,
            temperature: 0.2,
            topP: 0.95,
            repetitionPenalty: 1.05,
            repetitionContextSize: 64
        )
        let session = ChatSession(
            container,
            instructions: jsonOnlyInstructions,
            generateParameters: parameters
        )

        var output = ""
        for try await chunk in session.streamResponse(to: prompt) {
            try Task.checkCancellation()
            output += chunk
            await onChunk(chunk)
        }
        if output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw LocalLLMRunnerError.generationFailed
        }
        return output
    }

    private func resolvedContainer(modelPath: URL) async throws -> ModelContainer {
        if let cachedContainer, cachedModelDirectory == modelPath {
            return cachedContainer
        }
        let container = try await loadWeights(from: modelPath)
        cachedModelDirectory = modelPath
        cachedContainer = container
        return container
    }

    private func loadWeights(from modelPath: URL) async throws -> ModelContainer {
        let signpost = PerformanceSignposts.beginLLMLoad()
        defer { PerformanceSignposts.endLLMLoad(signpost) }
        return try await loadModelContainer(
            from: modelPath,
            using: MLXTokenizerBridge.localDirectoryLoader
        )
    }

    // MARK: - Pre-warming

    /// Whether model weights are currently held in memory (pre-warm or prior inference).
    var isLoaded: Bool { cachedContainer != nil }

    func releaseModel() {
        let signpost = PerformanceSignposts.beginLLMUnload(reason: "releaseModel")
        defer { PerformanceSignposts.endLLMUnload(signpost) }
        cachedContainer = nil
        cachedModelDirectory = nil
        Task { @MainActor in
            NotificationCenter.default.post(name: .llmModelDidUnload, object: nil)
        }
    }

    func preWarm(modelPath: URL) async {
        guard AppleSiliconPlatform.isSupported else { return }
        guard cachedContainer == nil || cachedModelDirectory != modelPath else { return }
        await MainActor.run { LLMMemoryLifecycle.shared.cancelIdleRelease() }
        do {
            let container = try await MLXTaskQueue.shared.run(priority: .utility) {
                try await self.loadWeights(from: modelPath)
            }
            cachedModelDirectory = modelPath
            cachedContainer = container
            await MainActor.run { LLMMemoryLifecycle.shared.touch() }
        } catch {
            // Pre-warm is best-effort; ignore errors silently
        }
    }

    private func requireSupportedMetalDevice() throws {
        guard AppleSiliconPlatform.isSupported else {
            throw LocalLLMRunnerError.unavailable(AppleSiliconPlatform.requirementMessage)
        }
    }
}
