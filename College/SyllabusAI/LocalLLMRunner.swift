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
/// **Re-entrancy safety**: MLX does not support concurrent inference on the same GPU/ANE.
/// Callers queue here and are released one at a time. This prevents crashes and garbage output
/// that would otherwise occur when multiple `Task`s interleave inside a suspended actor.
actor LocalLLMRunner {
    static let shared = LocalLLMRunner()

    private var cachedModelDirectory: URL?
    private var cachedContainer: ModelContainer?
    private let maxPendingRequests = 24

    // MARK: - Inference Serialization Queue
    private var isGenerating = false
    private var pendingWaiters: [CheckedContinuation<Void, Never>] = []

    /// Suspends the caller until the inference slot is free, then marks it as taken.
    private func acquireSlot() async throws {
        guard isGenerating else {
            isGenerating = true
            return
        }
        guard pendingWaiters.count < maxPendingRequests else {
            throw LocalLLMRunnerError.unavailable("Local model is busy. Please try again in a moment.")
        }
        await withCheckedContinuation { cont in
            pendingWaiters.append(cont)
        }
        // The continuation is resumed by releaseSlot(), which leaves isGenerating = true
        // so that this newly-resumed caller can proceed without re-checking.
    }

    /// Releases the inference slot, waking the next queued caller if any.
    private func releaseSlot() {
        if let next = pendingWaiters.first {
            pendingWaiters.removeFirst()
            next.resume() // isGenerating stays true — slot is handed off directly
        } else {
            isGenerating = false
        }
    }

    // MARK: - Inference

    /// Single integration point for all on-device LLM inference (Gemma 4 via MLXLLM).
    func generateJSON(prompt: String, modelPath: URL, maxTokens: Int = 700) async throws -> String {
        if LocalLLMStubResponder.shouldHandle() {
            return try await LocalLLMStubResponder.response(prompt: prompt)
        }
        try await acquireSlot()
        defer { releaseSlot() }

        let container: ModelContainer
        if let cachedContainer, cachedModelDirectory == modelPath {
            container = cachedContainer
        } else {
            // Loads from an already-downloaded on-disk model directory.
            // The MLXLLM module is linked to ensure the LLM model factory is available.
            container = try await loadModelContainer(directory: modelPath)
            cachedModelDirectory = modelPath
            cachedContainer = container
        }

        // Strong JSON-only bias; downstream JSON sanitizer still handles minor deviations.
        let jsonOnlyInstructions =
            "You are a careful parser. Return ONLY valid JSON. No markdown, no code fences, no extra commentary."

        let parameters = GenerateParameters(
            maxTokens: maxTokens,
            temperature: 0.2,
            topP: 0.95,
            repetitionPenalty: 1.05,
            repetitionContextSize: 64
        )

        // A fresh ChatSession per call ensures conversation history doesn't contaminate
        // independent parse tasks, while the cached ModelContainer avoids re-loading weights.
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
        try await acquireSlot()
        defer { releaseSlot() }

        let container: ModelContainer
        if let cachedContainer, cachedModelDirectory == modelPath {
            container = cachedContainer
        } else {
            container = try await loadModelContainer(directory: modelPath)
            cachedModelDirectory = modelPath
            cachedContainer = container
        }

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

    /// Same JSON contract as ``generateJSON``, but optionally includes up to four images for Gemma 4 vision.
    func generateJSONWithOptionalImages(
        prompt: String,
        imageURLs: [URL],
        modelPath: URL,
        maxTokens: Int = 700
    ) async throws -> String {
        if LocalLLMStubResponder.shouldHandle() {
            return try await LocalLLMStubResponder.response(prompt: prompt)
        }
        try await acquireSlot()
        defer { releaseSlot() }

        let container: ModelContainer
        if let cachedContainer, cachedModelDirectory == modelPath {
            container = cachedContainer
        } else {
            container = try await loadModelContainer(directory: modelPath)
            cachedModelDirectory = modelPath
            cachedContainer = container
        }

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

        let capped = Array(imageURLs.prefix(4))
        let output: String
        if capped.isEmpty {
            output = try await session.respond(to: prompt)
        } else {
            let images = capped.map { UserInput.Image.url($0) }
            output = try await session.respond(to: prompt, images: images, videos: [])
        }

        if output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw LocalLLMRunnerError.generationFailed
        }
        return output
    }

    /// Streaming variant for multimodal JSON generation.
    func generateJSONWithOptionalImagesStreaming(
        prompt: String,
        imageURLs: [URL],
        modelPath: URL,
        maxTokens: Int = 700,
        onChunk: @escaping @Sendable (String) async -> Void
    ) async throws -> String {
        if LocalLLMStubResponder.shouldHandle() {
            return try await LocalLLMStubResponder.responseStreaming(prompt: prompt, onChunk: onChunk)
        }
        try await acquireSlot()
        defer { releaseSlot() }

        let container: ModelContainer
        if let cachedContainer, cachedModelDirectory == modelPath {
            container = cachedContainer
        } else {
            container = try await loadModelContainer(directory: modelPath)
            cachedModelDirectory = modelPath
            cachedContainer = container
        }

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

        let capped = Array(imageURLs.prefix(4))
        var output = ""
        let stream: AsyncThrowingStream<String, Error> = {
            if capped.isEmpty {
                return session.streamResponse(to: prompt)
            }
            let images = capped.map { UserInput.Image.url($0) }
            return session.streamResponse(to: prompt, images: images, videos: [])
        }()

        for try await chunk in stream {
            try Task.checkCancellation()
            output += chunk
            await onChunk(chunk)
        }

        if output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw LocalLLMRunnerError.generationFailed
        }
        return output
    }

    // MARK: - Pre-warming

    /// Loads the model weights into memory without running inference.
    /// Call this at low priority when the model is installed but before the user
    /// drops a syllabus, so the 5–20 s weight-load cost is paid in the background.
    func preWarm(modelPath: URL) async {
        guard cachedContainer == nil || cachedModelDirectory != modelPath else { return }
        guard !isGenerating else { return } // Don't compete with active inference
        do {
            let container = try await loadModelContainer(directory: modelPath)
            cachedModelDirectory = modelPath
            cachedContainer = container
        } catch {
            // Pre-warm is best-effort; ignore errors silently
        }
    }
}
