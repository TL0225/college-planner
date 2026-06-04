import Foundation
import MLXLMCommon
import VecturaMLXKit

public enum VecturaSentenceAdapterError: Error, Sendable {
    case emptyEmbedding
}

/// Loads weights from a local `ModelConfiguration(directory:)` layout (e.g. app `CatalogEmbed` folders).
public actor VecturaMLXSentenceAdapter: IsolatedSentenceEmbedding768 {
    private let embedder: MLXEmbedder

    public init(modelDirectory: URL) async throws {
        embedder = try await MLXEmbedder(configuration: ModelConfiguration(directory: modelDirectory))
    }

    public func embedNormalized768(text: String) async throws -> [Float] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let vectors = try await embedder.embed(texts: [trimmed])
        guard let first = vectors.first else { throw VecturaSentenceAdapterError.emptyEmbedding }
        return first
    }
}
