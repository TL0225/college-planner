// CatalogChunkProjectionStoreTests.swift
// Feature: Catalog
// Purpose: Catalog module — CatalogChunkProjectionStoreTests.
// Data: CollegePersistence / repositories when applicable.

import SwiftData
import XCTest
@testable import College

final class CatalogChunkProjectionStoreTests: PersistenceTestCase {
    override var includesCatalog: Bool { true }

    func testCourseCatalogProducesDeterministicChunks() throws {
        let ctx = try XCTUnwrap(catalogContext)
        let uniID = UUID()
        let courseID = UUID()
        let uni = University(id: uniID, name: "Chunk U", isActive: true)
        let course = CourseCatalog(
            id: courseID,
            courseCode: "CSE 220",
            title: "Systems Programming",
            credits: 4,
            isHydrated: true
        )
        course.descriptionText = "Low-level programming and systems."
        course.university = uni
        ctx.insert(uni)
        try ctx.save()

        let chunks = CatalogChunkProjection.chunks(from: course)
        XCTAssertFalse(chunks.isEmpty)
        XCTAssertEqual(chunks.first?.universityID, uniID)
        XCTAssertEqual(chunks.first?.sourceKind, "course")
        XCTAssertEqual(chunks.first?.courseCode, "CSE 220")
        XCTAssertTrue(chunks.first?.chunkId.hasPrefix("course:\(courseID.uuidString)#") == true)
    }

    func testPolicyDocumentProducesSingleChunk() throws {
        let ctx = try XCTUnwrap(catalogContext)
        let uni = University(name: "Policy U", isActive: true)
        ctx.insert(uni)
        let policy = CatalogPolicyDocument(
            catoid: "2024",
            sourceURL: "https://example.edu/policy",
            navTitle: "Academic Integrity",
            bodyText: "Students must follow the honor code.",
            catalogScope: "university",
            contentHash: "abc123"
        )
        policy.university = uni
        try ctx.save()

        let chunks = CatalogChunkProjection.chunks(from: policy)
        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks.first?.sourceKind, "catalog_policy")
        XCTAssertEqual(chunks.first?.catalogScope, "university")
    }
}
