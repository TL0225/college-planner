import Foundation

/// App-facing contract for 768-D normalized sentence embeddings without pulling `VecturaMLXKit` into the main target graph.
public protocol IsolatedSentenceEmbedding768: Sendable {
    func embedNormalized768(text: String) async throws -> [Float]
}
