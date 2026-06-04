// CatalogModernBERTPhase0Spike.swift
// Feature: Catalog
// Purpose: Catalog module — CatalogModernBERTPhase0Spike.
// Data: CollegePersistence / repositories when applicable.

import Foundation

/// Phase 0 “bedrock” check: confirm an MLX sentence bundle produces **768** finite floats for the canonical probe string
/// on the same ``CatalogMLXEmbedService`` path (including ``MLXTaskQueue`` inside the service) as ``CatalogEmbeddingRuntime``.
///
/// **VecturaMLXKit:** Not linked in this app target — see ``VecturaMLXKitIsolationNotes`` and the standalone `VecturaService` package.
/// for the planned framework boundary. The numeric contract (768-d) uses bundle-first or staged
/// ``CatalogMLXEmbedPaths/resolvedModelDirectoryURL()`` when `config.json` is present.
enum CatalogModernBERTPhase0Spike {
    /// Canonical probe from the product plan (policy RAG smoke string).
    static let probeText = "Academic Policy"

    enum SpikeError: Error, Sendable {
        case wrongDimension(expected: Int, actual: Int)
        case nonFiniteValues
    }

    /// Runs only when `config.json` exists under bundle-first or staged ``CatalogMLXEmbedPaths/resolvedModelDirectoryURL()``; otherwise returns `nil`.
    static func embedProbeIfMLXBundlePresent() async throws -> [Float]? {
        guard let dir = CatalogMLXEmbedPaths.resolvedModelDirectoryURL() else { return nil }
        let vector = try await CatalogMLXEmbedService.shared.embedNormalized(
            text: Self.probeText,
            modelDirectory: dir,
            priority: .utility
        )
        guard vector.count == CatalogLexicalEmbedding.dimension else {
            throw SpikeError.wrongDimension(expected: CatalogLexicalEmbedding.dimension, actual: vector.count)
        }
        guard vector.allSatisfy(\.isFinite) else {
            throw SpikeError.nonFiniteValues
        }
        return vector
    }
}
