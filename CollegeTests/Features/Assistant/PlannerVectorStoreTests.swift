// PlannerVectorStoreTests.swift
import Foundation
import Testing
@testable import College

@Suite("Planner Vector Store")
struct PlannerVectorStoreTests {

    @Test("Upsert and search")
    func upsertAndSearch() async throws {
        let store = PlannerVectorStore(inMemory: true)
        try await store.upsert(
            chunkId: "c1",
            sourceType: "calendar_event",
            sourceId: "e1",
            segmentIndex: 0,
            ftsBody: "CSC 316 lecture Hall B tomorrow",
            metadataJSON: "{}",
            contentHash: "h1",
            embeddingVersion: PlannerVectorSearchConfig.embeddingVersion,
            referenceDate: Date(),
            embedding: nil
        )
        let hits = try await store.searchHybrid(
            query: "CSC 316 Hall",
            ftsPrefetch: 8,
            limit: 4,
            queryVector: nil,
            semanticEnabled: false
        )
        #expect(!hits.isEmpty)
        #expect(hits.first?.row.sourceId == "e1")
    }

    @Test("Chunk count")
    func chunkCount() async throws {
        let store = PlannerVectorStore(inMemory: true)
        let count = try await store.chunkCount()
        #expect(count == 0)
    }
}
