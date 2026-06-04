// CatalogEmbeddingRuntime.swift
// Feature: Catalog
// Purpose: Catalog module — CatalogEmbeddingRuntime.
// Data: CollegePersistence / repositories when applicable.

import Foundation

/// Bundles catalog query/document embeddings behind ``MLXTaskQueue`` so Gemma and sentence embedders never share the GPU unsafely.
actor CatalogEmbeddingRuntime {
    static let shared = CatalogEmbeddingRuntime()

    private nonisolated static let lexicalEmbeddingVersion = "catalog.lexical768.v3"
    private nonisolated static let mlxEmbeddingVersion = "catalog.mlx_sentence.v3_bundle_first"

    /// ~500–1k-token budget (conservative char split pre tokenization) so ``MLXTaskQueue`` can service `.userInitiated` between chunks.
    private nonisolated static let embedSubChunkMaxCharacters = 2400

    /// Distinct per vector formula; MLX vs lexical must never share rows with the same version string.
    nonisolated static var embeddingVersion: String {
        CatalogMLXEmbedPaths.resolvedModelDirectoryURL() != nil
            ? mlxEmbeddingVersion
            : lexicalEmbeddingVersion
    }

    func embed(text: String, priority: MLXTaskPriority) async throws -> [Float] {
        await MainActor.run { CatalogEmbedMemoryLifecycle.shared.cancelIdleRelease() }
        defer {
            Task { @MainActor in
                CatalogEmbedMemoryLifecycle.shared.touch()
            }
        }

        let clipped = String(text.prefix(8000))
        if clipped.count <= Self.embedSubChunkMaxCharacters {
            return try await embedSubChunk(clipped, priority: priority)
        }

        var vectors: [[Float]] = []
        vectors.reserveCapacity(max(1, clipped.count / Self.embedSubChunkMaxCharacters))

        var idx = clipped.startIndex
        while idx < clipped.endIndex {
            let end = clipped.index(
                idx,
                offsetBy: Self.embedSubChunkMaxCharacters,
                limitedBy: clipped.endIndex
            ) ?? clipped.endIndex
            let part = String(clipped[idx..<end])
            idx = end
            guard !part.isEmpty else { continue }
            vectors.append(try await embedSubChunk(part, priority: priority))
        }

        guard !vectors.isEmpty else {
            return try await embedSubChunk(clipped, priority: priority)
        }
        return Self.meanL2Normalize(vectors)
    }

    private func embedSubChunk(_ text: String, priority: MLXTaskPriority) async throws -> [Float] {
        if let dir = CatalogMLXEmbedPaths.resolvedModelDirectoryURL() {
            return try await CatalogMLXEmbedService.shared.embedNormalized(
                text: text,
                modelDirectory: dir,
                priority: priority
            )
        }
        return try await MLXTaskQueue.shared.run(priority: priority) {
            CatalogLexicalEmbedding.normalizedVector(for: text)
        }
    }

    private nonisolated static func meanL2Normalize(_ vectors: [[Float]]) -> [Float] {
        guard let dim = vectors.first?.count, dim > 0 else { return [] }
        var acc = [Float](repeating: 0, count: dim)
        var used = 0
        for v in vectors where v.count == dim {
            used += 1
            for i in 0..<dim {
                acc[i] += v[i]
            }
        }
        guard used > 0 else { return vectors.first ?? [] }
        let inv = 1 / Float(used)
        for i in 0..<dim {
            acc[i] *= inv
        }
        return l2Normalize(acc)
    }

    private nonisolated static func l2Normalize(_ v: [Float]) -> [Float] {
        let sq = v.reduce(0) { $0 + $1 * $1 }
        let n = sqrt(sq)
        guard n > 1e-6 else { return v }
        return v.map { $0 / n }
    }
}
