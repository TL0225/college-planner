// CatalogSanityConstraintsTests.swift
// Feature: Catalog
// Purpose: Baseline sanity checks must not block rescrapes after catalog discovery changes.

import XCTest
@testable import College

final class CatalogSanityConstraintsTests: XCTestCase {
    private let schoolID = "university_at_buffalo_test"
    private let catalogVersionID = "manifest-only-test"

    override func tearDown() {
        CatalogExtractorMetricsBaselineStore.clear(schoolID: schoolID, catalogVersionID: catalogVersionID)
        super.tearDown()
    }

    func testEvaluate_blocksWhenProgramCountDropsBelowBaseline() {
        CatalogExtractorMetricsBaselineStore.save(
            CatalogExtractorMetrics(
                schoolID: schoolID,
                catalogVersionID: catalogVersionID,
                source: "moderncampus",
                layoutProfileID: nil,
                programsFound: 1_000,
                coursesFound: 0,
                requirementsFound: 0,
                policiesFound: 0,
                requirementTablesFound: 0,
                averageEntityConfidence: nil,
                averageOwnershipConfidence: nil,
                recordedAt: Date()
            )
        )

        let result = CatalogSanityConstraints.evaluate(
            metrics: CatalogExtractorMetrics(
                schoolID: schoolID,
                catalogVersionID: catalogVersionID,
                source: "moderncampus",
                layoutProfileID: nil,
                programsFound: 400,
                coursesFound: 0,
                requirementsFound: 0,
                policiesFound: 0,
                requirementTablesFound: 0,
                averageEntityConfidence: nil,
                averageOwnershipConfidence: nil,
                recordedAt: Date()
            ),
            expectCourses: false,
            expectPrograms: true
        )

        XCTAssertFalse(result.passed)
        XCTAssertEqual(result.severity, .critical)
    }

    func testEvaluate_allowsRescrapeAfterBaselineCleared() {
        CatalogExtractorMetricsBaselineStore.save(
            CatalogExtractorMetrics(
                schoolID: schoolID,
                catalogVersionID: catalogVersionID,
                source: "moderncampus",
                layoutProfileID: nil,
                programsFound: 1_000,
                coursesFound: 0,
                requirementsFound: 0,
                policiesFound: 0,
                requirementTablesFound: 0,
                averageEntityConfidence: nil,
                averageOwnershipConfidence: nil,
                recordedAt: Date()
            )
        )
        CatalogExtractorMetricsBaselineStore.clear(schoolID: schoolID, catalogVersionID: catalogVersionID)

        let result = CatalogSanityConstraints.evaluate(
            metrics: CatalogExtractorMetrics(
                schoolID: schoolID,
                catalogVersionID: catalogVersionID,
                source: "moderncampus",
                layoutProfileID: nil,
                programsFound: 400,
                coursesFound: 0,
                requirementsFound: 0,
                policiesFound: 0,
                requirementTablesFound: 0,
                averageEntityConfidence: nil,
                averageOwnershipConfidence: nil,
                recordedAt: Date()
            ),
            expectCourses: false,
            expectPrograms: true
        )

        XCTAssertTrue(result.passed)
    }
}
