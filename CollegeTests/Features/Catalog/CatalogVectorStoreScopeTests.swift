// CatalogVectorStoreScopeTests.swift
// Feature: Catalog
// Purpose: Catalog module — CatalogVectorStoreScopeTests.
// Data: CollegePersistence / repositories when applicable.

import XCTest
@testable import College

final class CatalogVectorStoreScopeTests: XCTestCase {

    func testCatalogScopeSqlFilterIncludesMatchingPolicyRows() async throws {
        let store = CatalogVectorStore(inMemory: true)
        let uid = UUID()

        try await store.upsert(
            chunkId: "policy:grad",
            universityId: uid,
            sourceKind: "catalog_policy",
            ftsBody: "grading rules graduate tier alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu nu xi omicron pi rho sigma tau upsilon phi chi psi omega",
            metadataJSON: "{}",
            contentHash: "h1",
            embeddingVersion: "t",
            embedding: nil,
            courseCode: nil,
            programURL: nil,
            requirementCategory: nil,
            catalogScope: "graduate"
        )
        try await store.upsert(
            chunkId: "policy:ugrad",
            universityId: uid,
            sourceKind: "catalog_policy",
            ftsBody: "grading rules undergraduate tier alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu nu xi omicron pi rho sigma tau upsilon phi chi psi omega",
            metadataJSON: "{}",
            contentHash: "h2",
            embeddingVersion: "t",
            embedding: nil,
            courseCode: nil,
            programURL: nil,
            requirementCategory: nil,
            catalogScope: "undergraduate"
        )
        try await store.upsert(
            chunkId: "course:c1",
            universityId: uid,
            sourceKind: "course",
            ftsBody: "grading syllabus course alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu nu xi omicron pi rho sigma tau upsilon phi chi psi omega",
            metadataJSON: "{}",
            contentHash: "h3",
            embeddingVersion: "t",
            embedding: nil,
            courseCode: "MATH101",
            programURL: nil,
            requirementCategory: nil,
            catalogScope: ""
        )

        let undergradRows = try await store.searchHybrid(
            query: "grading",
            universityId: uid,
            ftsPrefetch: 50,
            limit: 10,
            queryVector: nil,
            semanticEnabled: false,
            catalogScopeFilter: "undergraduate",
            preferredProgramURL: nil
        )
        let ids = Set(undergradRows.map(\.chunkId))
        XCTAssertTrue(ids.contains("policy:ugrad"))
        XCTAssertTrue(ids.contains("course:c1"))
        XCTAssertFalse(ids.contains("policy:grad"))

        let gradRows = try await store.searchHybrid(
            query: "grading",
            universityId: uid,
            ftsPrefetch: 50,
            limit: 10,
            queryVector: nil,
            semanticEnabled: false,
            catalogScopeFilter: "graduate",
            preferredProgramURL: nil
        )
        let idsG = Set(gradRows.map(\.chunkId))
        XCTAssertTrue(idsG.contains("policy:grad"))
        XCTAssertTrue(idsG.contains("course:c1"))
        XCTAssertFalse(idsG.contains("policy:ugrad"))
    }
}
