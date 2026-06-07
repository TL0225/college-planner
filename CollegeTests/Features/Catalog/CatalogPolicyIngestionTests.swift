// CatalogPolicyIngestionTests.swift
// Feature: Catalog
// Purpose: Catalog module — CatalogPolicyIngestionTests.
// Data: CollegePersistence / repositories when applicable.

import XCTest
@testable import College

final class CatalogPolicyIngestionTests: XCTestCase {

    func testCatalogPolicyScopeClassifierFromCatalogLabel() {
        XCTAssertEqual(
            CatalogPolicyScopeClassifier.scope(catalogTypeLabel: "Undergraduate", navLinkText: nil).rawValue,
            "undergraduate"
        )
        XCTAssertEqual(
            CatalogPolicyScopeClassifier.scope(catalogTypeLabel: "Graduate", navLinkText: nil).rawValue,
            "graduate"
        )
        XCTAssertEqual(
            CatalogPolicyScopeClassifier.scope(catalogTypeLabel: "Law School", navLinkText: nil).rawValue,
            "graduate"
        )
        XCTAssertEqual(
            CatalogPolicyScopeClassifier.scope(catalogTypeLabel: "Catalog 42", navLinkText: "Undergraduate Grading").rawValue,
            "undergraduate"
        )
    }

    func testRetrievalFilterToken() {
        XCTAssertEqual(
            CatalogPolicyScopeClassifier.retrievalFilterToken(degreeLevel: "Graduate", degreeType: "MS"),
            "graduate"
        )
        XCTAssertEqual(
            CatalogPolicyScopeClassifier.retrievalFilterToken(degreeLevel: "Undergraduate", degreeType: "BS"),
            "undergraduate"
        )
        XCTAssertEqual(
            CatalogPolicyScopeClassifier.retrievalFilterToken(degreeLevel: "", degreeType: "PhD"),
            "graduate"
        )
    }

    func testHeadingChunkerSplitsOnH2() throws {
        let html = """
        <html><body><div id="acalog-content">
        <h2>Repeating a Course</h2>
        <p>First paragraph about repeats and satisfies the minimum length guard for policy chunks in the indexer.</p>
        <h2>Withdrawal</h2>
        <p>Second paragraph about withdrawal deadlines and satisfies the minimum length guard for policy chunks too.</p>
        </div></body></html>
        """
        let sections = try ModernCampusPolicyIngestion.test_policySections(
            html: html,
            baseURL: "https://catalog.example.edu/content.php?catoid=1&navoid=2",
            navTitle: "Academic Regulations"
        )
        XCTAssertGreaterThanOrEqual(sections.count, 1)
        let joined = sections.map { "\($0.heading):\($0.text)" }.joined(separator: "|")
        XCTAssertTrue(joined.contains("Repeating"))
        XCTAssertTrue(joined.contains("Withdrawal"))
    }

    func testHeadingSiblingPassCapturesDivOnlyUnderH2() throws {
        let html = """
        <html><body><div id="acalog-content">
        <h2>Withdrawal</h2>
        <div>This paragraph is not wrapped in p tags but should still be captured by the sibling-tail pass with enough length for chunking.</div>
        </div></body></html>
        """
        let sections = try ModernCampusPolicyIngestion.test_policySections(
            html: html,
            baseURL: "https://catalog.example.edu/content.php?catoid=1&navoid=2",
            navTitle: "Policies"
        )
        XCTAssertFalse(sections.isEmpty)
        let blob = sections.map { "\($0.heading):\($0.text)" }.joined(separator: "|")
        XCTAssertTrue(blob.localizedCaseInsensitiveContains("withdrawal"))
    }

    func testModernBERTPhase0SpikeSkipsWithoutBundle() async throws {
        guard CatalogMLXEmbedPaths.resolvedModelDirectoryURL() != nil else {
            let v = try await CatalogModernBERTPhase0Spike.embedProbeIfMLXBundlePresent()
            XCTAssertNil(v)
            return
        }
        let v = try await CatalogModernBERTPhase0Spike.embedProbeIfMLXBundlePresent()
        XCTAssertNotNil(v)
        XCTAssertEqual(v?.count, CatalogLexicalEmbedding.dimension)
        XCTAssertTrue(v!.allSatisfy(\.isFinite))
    }
}
