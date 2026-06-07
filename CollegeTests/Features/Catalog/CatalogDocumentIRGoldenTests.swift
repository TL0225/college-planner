// CatalogDocumentIRGoldenTests.swift
// Feature: Shared
// Purpose: Offline DOM analyzer golden — section paths, profile ID, node counts.
// Data: CollegePersistence / repositories when applicable.

import XCTest
@testable import College

final class CatalogDocumentIRGoldenTests: XCTestCase {
    func testFordhamFixture_domAnalysisAndIR() throws {
        let xml = try TestFixturePaths.courseLeafString(named: "fordham_aast_courses.xml")
        let pageURL = URL(string: "https://bulletin.fordham.edu/courses/aast/")!
        let analysis = CatalogCourseLeafDOMAnalyzer.analyze(
            xml: xml,
            pageURL: pageURL,
            schoolID: "fordham_university",
            catalogVersionID: "fordham-undergrad"
        )
        let (profileID, confidence) = CourseLeafLayoutClassifier.classify(domFeatures: analysis.domFeatures)
        XCTAssertFalse(profileID.isEmpty)
        XCTAssertGreaterThan(confidence, 0)
        XCTAssertGreaterThan(analysis.domFeatures.courseblocktitleCount + analysis.domFeatures.dlCourseblockCount, 0)

        let layoutID = CatalogLayoutProfileRegistry.preferredProfileID(forSchoolID: "fordham_university")?.rawValue ?? profileID
        let ir = CatalogCourseLeafDOMAnalyzer.buildIR(
            schoolID: "fordham_university",
            catalogVersionID: "fordham-undergrad",
            analysis: analysis,
            layoutProfileID: layoutID,
            layoutConfidence: CatalogExtractionConfidence(score: confidence, reasons: ["test"])
        )
        XCTAssertGreaterThan(analysis.nodes.count, 0)
        XCTAssertEqual(ir.layoutProfileID, layoutID)
    }
}
