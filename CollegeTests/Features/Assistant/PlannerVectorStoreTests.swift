// PlannerVectorStoreTests.swift
// Feature: Assistant
// Purpose: Assistant module — PlannerVectorStoreTests.
// Data: CollegePersistence / repositories when applicable.

import XCTest
@testable import College

final class PlannerVectorStoreTests: XCTestCase {
    func testUpsertAndSearch() async throws {
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
        XCTAssertFalse(hits.isEmpty)
        XCTAssertEqual(hits.first?.row.sourceId, "e1")
    }

    func testChunkCount() async throws {
        let store = PlannerVectorStore(inMemory: true)
        let count = try await store.chunkCount()
        XCTAssertEqual(count, 0)
    }
}
