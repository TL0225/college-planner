// CatalogChunkProjection.swift
// Feature: Catalog
// Purpose: Catalog module — IndexedChunk.
// Data: CollegePersistence / repositories when applicable.

import CryptoKit
import Foundation

/// Deterministic catalog text + stable ids for SQLite vector index rows (local store + legacy CD extensions).
enum CatalogChunkProjection {
    struct IndexedChunk: Sendable, Equatable {
        let chunkId: String
        let universityID: UUID
        let sourceKind: String
        let ftsBody: String
        let courseCode: String?
        let programURL: String?
        let requirementCategory: String?
        /// Stored in FTS as `catalog_scope` for SQL-side policy tier pruning (`catalog_policy` rows only).
        let catalogScope: String
        let metadataJSON: String
        let contentHash: String
    }

    static func contentHash(for text: String) -> String {
        let digest = SHA256.hash(data: Data(text.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
