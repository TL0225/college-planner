// CatalogLexicalEmbedding.swift
// Feature: Catalog
// Purpose: Catalog module — CatalogLexicalEmbedding.
// Data: CollegePersistence / repositories when applicable.

import CryptoKit
import Foundation

/// Deterministic 768-dimensional unit vector used when no on-disk MLX embedding bundle is present.
/// **NVFP4 / ModernBERT:** When weights are added (e.g. via MLX community embedders or VecturaMLXKit), replace the
/// runtime body in `CatalogEmbeddingRuntime` while keeping `embeddingVersion` distinct so SQLite rows never mix.
enum CatalogLexicalEmbedding {
    static let dimension = 768

    /// L2-normalized vector suitable for cosine similarity with query vectors from the same function.
    static func normalizedVector(for text: String) -> [Float] {
        let digest = SHA256.hash(data: Data(text.utf8))
        var raw = [Float](repeating: 0, count: dimension)
        let bytes = Array(digest)
        var idx = 0
        var bytePos = 0
        while idx < dimension {
            let b0 = Float(bytes[bytePos % bytes.count]) / 255.0
            let b1 = Float(bytes[(bytePos + 1) % bytes.count]) / 255.0
            let b2 = Float(bytes[(bytePos + 2) % bytes.count]) / 255.0
            raw[idx] = sin(b0 * 6.28318530718 + Float(idx) * 0.01) * 0.25
                + cos(b1 * 6.28318530718 + Float(idx) * 0.02) * 0.25
                + sin(b2 * 3.14159265359 + Float(idx) * 0.03) * 0.25
            idx += 1
            bytePos += 3
        }
        var sumSq: Float = 0
        for v in raw { sumSq += v * v }
        let norm = sqrt(sumSq)
        guard norm > 0 else { return raw }
        return raw.map { $0 / norm }
    }
}
