// PlannerVectorIndexer.swift
// Feature: Assistant
// Purpose: Assistant module — PlannerVectorIndexer.
// Data: CollegePersistence / repositories when applicable.

// Isolation: `actor PlannerVectorIndexer` — background indexing; not `@MainActor`.

import Foundation

/// Projects local store planner rows into ``PlannerVectorStore`` with lexical sketch embeddings.
actor PlannerVectorIndexer {
    static let shared = PlannerVectorIndexer()

    private(set) var isIndexing: Bool = false

    func startObservingSaves(container: Any? = nil) {
        _ = container
    }

    func stopObservingSaves() {}

    func runFullRebuild(reason: String) async {
        guard AssistantPlannerIndexingSettings.isIndexingEnabled else { return }
        guard !isIndexing else { return }
        isIndexing = true
        defer { isIndexing = false }

        let shadow = PlannerVectorStore.openShadowBuildStore()

        do {
            let payloads = await MainActor.run {
                PlannerChunkProjection.fetchAllChunks()
            }
            for chunk in payloads {
                try await Self.upsertChunk(chunk, into: shadow)
            }
            try await PlannerVectorStore.shared.swapFromShadowBuild(shadow)
            let count = try await PlannerVectorStore.shared.chunkCount()
            AssistantPlannerIndexingSettings.markIndexed(chunkCount: count)
            await MainActor.run {
                DebugLogger.shared.log(
                    "Planner vector index rebuilt: chunks=\(payloads.count) reason=\(reason)",
                    category: .system,
                    level: .info
                )
            }
        } catch {
            await MainActor.run {
                DebugLogger.shared.log(
                    "Planner vector rebuild failed: \(error.localizedDescription)",
                    category: .system,
                    level: .error
                )
            }
        }
    }

    func indexVaultBackfill() async {
        guard AssistantPlannerIndexingSettings.isIndexingEnabled,
              AssistantPlannerIndexingSettings.isDocumentsIndexingEnabled else { return }
        let ids = await MainActor.run {
            (try? CollegePersistence.shared.vaultRepository.fetchDocuments(limit: 5000))?
                .filter { !$0.isFolder }
                .map(\.id) ?? []
        }
        for id in ids {
            await VaultDocumentTextIndexer.shared.schedule(documentID: id)
            await Task.yield()
        }
    }

    private static func upsertChunk(
        _ chunk: PlannerChunkProjection.IndexedChunk,
        into store: PlannerVectorStore
    ) async throws {
        let vec = AssistantWebMemoryEmbedding.vector(for: String(chunk.ftsBody.prefix(4_000)))
        let emb = AssistantWebMemoryEmbedding.data(from: vec)
        try await store.upsert(
            chunkId: chunk.chunkId,
            sourceType: chunk.sourceType,
            sourceId: chunk.sourceId,
            segmentIndex: chunk.segmentIndex,
            ftsBody: chunk.ftsBody,
            metadataJSON: chunk.metadataJSON,
            contentHash: chunk.contentHash,
            embeddingVersion: PlannerVectorSearchConfig.embeddingVersion,
            referenceDate: chunk.referenceDate,
            embedding: emb
        )
    }
}
