// CatalogPlatformServicesTests.swift
// Feature: Catalog
// Purpose: Unit tests for catalog platform services (P7-P31).

import XCTest
@testable import College

final class CatalogPlatformServicesTests: XCTestCase {
    func testLayoutIRReadingOrder() {
        let lines = [
            CatalogPDFLine(text: "LEFT A", pageIndex: 0, lineIndexOnPage: 0, rect: CGRect(x: 10, y: 100, width: 80, height: 12)),
            CatalogPDFLine(text: "RIGHT A", pageIndex: 0, lineIndexOnPage: 1, rect: CGRect(x: 320, y: 100, width: 80, height: 12)),
            CatalogPDFLine(text: "LEFT B", pageIndex: 0, lineIndexOnPage: 2, rect: CGRect(x: 10, y: 120, width: 80, height: 12)),
        ]
        let ordered = CatalogPDFLayoutIRBuilder.reorderLinesForReadingOrder(lines)
        XCTAssertEqual(ordered.first?.text, "LEFT A")
        let blocks = CatalogPDFLayoutIRBuilder.build(from: ordered)
        XCTAssertFalse(blocks.isEmpty)
    }

    func testTableIRParsesPipeRows() {
        let block = CatalogPDFLayoutBlock(
            page: 1,
            boundingBox: nil,
            text: "CODE | TITLE\nACCT 2001 | Financial Accounting\nACCT 2002 | Managerial Accounting",
            blockType: .table,
            readingOrder: 0
        )
        let tables = CatalogPDFTableIRBuilder.build(from: [block])
        XCTAssertEqual(tables.count, 1)
        XCTAssertGreaterThanOrEqual(tables[0].rows.count, 2)
    }

    func testEvaluationFrameworkOQS() {
        let report = CatalogEvaluationFramework.score(
            schoolID: "fordham_university",
            catalogVersionID: "fordham",
            programsFound: 10,
            coursesFound: 100,
            requirementsFound: 40,
            benchmarkPrecision: 0.8,
            benchmarkRecall: 0.7,
            requirementPrecision: 0.75,
            requirementRecall: 0.65
        )
        XCTAssertGreaterThan(report.overallQualityScore, 0.4)
    }

    func testSchoolTierRegistry() {
        XCTAssertEqual(CatalogSchoolTierRegistry.tier(for: "fordham_university"), .development)
        XCTAssertEqual(CatalogSchoolTierRegistry.tier(for: "unknown_school"), .heldOut)
    }

    func testRequirementASTRoundTrip() {
        let predicate = RequirementPredicate.all([
            .course(CourseDetail(code: "CSCI 101", title: "Intro", credits: "3"))
        ])
        let json = CatalogRequirementAST.encode(predicate)
        let decoded = CatalogRequirementAST.decode(from: json)
        XCTAssertEqual(decoded?.type, .all)
    }

    func testSemanticDiffDetectsCreditChange() {
        let before = [DegreeRequirement(degreeType: "BS", major: "CS", category: "Core", creditsRequired: 12)]
        let after = [DegreeRequirement(degreeType: "BS", major: "CS", category: "Core", creditsRequired: 15)]
        let diff = CatalogSemanticDiffEngine.diff(
            beforePrograms: ["CS"],
            afterPrograms: ["CS"],
            beforeRequirements: before,
            afterRequirements: after
        )
        XCTAssertEqual(diff.creditChanges.count, 1)
    }

    func testAuditReadinessScorer() {
        let reqs = [DegreeRequirement(degreeType: "BS", major: "CS", category: "Core", creditsRequired: 12)]
        let courses = [CatalogCourse(courseCode: "CSCI 101", title: "Intro", credits: 3, prerequisiteText: "MATH 101")]
        let report = CatalogAuditReadinessScorer.scoreProgram(name: "CS", requirements: reqs, courses: courses)
        XCTAssertGreaterThan(report.score, 0.5)
    }

    func testCapabilityMatrixTSV() {
        let row = CatalogCapabilityMatrix.buildRow(
            schoolID: "fordham_university",
            health: CatalogPDFHealthReport(pageCount: 100, outlineEntryCount: 5, lowTextDensityPages: 2, estimatedOCRPages: 1, layoutNote: "two_column"),
            evaluation: CatalogEvaluationFramework.score(
                schoolID: "fordham_university",
                catalogVersionID: "fordham",
                programsFound: 5,
                coursesFound: 50,
                requirementsFound: 20,
                benchmarkPrecision: 0.7,
                benchmarkRecall: 0.6,
                requirementPrecision: nil,
                requirementRecall: nil
            ),
            auditReadiness: 0.8
        )
        XCTAssertTrue(CatalogCapabilityMatrix.tsvLine(row).contains("fordham_university"))
    }
}
