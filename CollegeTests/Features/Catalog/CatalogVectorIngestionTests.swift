// CatalogVectorIngestionTests.swift
// Feature: Catalog
// Purpose: Catalog module — CatalogVectorIngestionTests.
// Data: CollegePersistence / repositories when applicable.

import XCTest
@testable import College

final class CatalogVectorIngestionTests: XCTestCase {

    func testLexicalEmbeddingSmoke768() {
        let v = CatalogLexicalEmbedding.normalizedVector(for: "CSE 113 — deterministic fixture")
        XCTAssertEqual(v.count, CatalogLexicalEmbedding.dimension)
        var sum: Float = 0
        for x in v { sum += x * x }
        XCTAssertEqual(sum, 1, accuracy: 0.001)
    }

    func testVectorMathCosineSelfOne() {
        let v: [Float] = [1, 0, 0, 0]
        guard let c = VectorMath.cosineSimilarity(v, v) else {
            XCTFail("expected cosine")
            return
        }
        XCTAssertEqual(c, 1, accuracy: 0.0001)
    }

    func testProjectionHashStability() {
        let text = """
        Course CSE 113: Introduction to Software Engineering
        Department: Computer Science
        Credits: 4
        Description: Test description for hashing stability.
        """
        let h1 = CatalogChunkProjection.contentHash(for: text)
        let h2 = CatalogChunkProjection.contentHash(for: text)
        XCTAssertEqual(h1, h2)
        XCTAssertEqual(h1.count, 64)
    }
}
