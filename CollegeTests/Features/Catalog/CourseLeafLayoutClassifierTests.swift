// CourseLeafLayoutClassifierTests.swift
// Feature: Shared
// Purpose: Deterministic layout profile classification from DOM feature vectors.
// Data: CollegePersistence / repositories when applicable.

import XCTest
@testable import College

final class CourseLeafLayoutClassifierTests: XCTestCase {
    func testClassify_profileA_NYUStyleDetailCodes() {
        let features = CatalogDOMFeatures(
            detailCodeCount: 24,
            courseblocktitleCount: 0,
            divCourseblockCount: 24,
            dlCourseblockCount: 0,
            scCourselistCount: 0,
            detailTitleCount: 24
        )
        let (profileID, confidence) = CourseLeafLayoutClassifier.classify(domFeatures: features)
        XCTAssertEqual(profileID, CourseLeafLayoutProfileID.profileA.rawValue)
        XCTAssertGreaterThan(confidence, 0.5)
    }

    func testClassify_profileB_FordhamTitleLines() {
        let features = CatalogDOMFeatures(
            detailCodeCount: 0,
            courseblocktitleCount: 18,
            divCourseblockCount: 18,
            dlCourseblockCount: 0,
            courseblockextraCount: 12
        )
        let (profileID, confidence) = CourseLeafLayoutClassifier.classify(domFeatures: features)
        XCTAssertEqual(profileID, CourseLeafLayoutProfileID.profileB.rawValue)
        XCTAssertGreaterThan(confidence, 0.4)
    }

    func testClassify_profileC_CMUDlBlocks() {
        let features = CatalogDOMFeatures(
            detailCodeCount: 0,
            courseblocktitleCount: 0,
            divCourseblockCount: 0,
            dlCourseblockCount: 15,
            scCourselistCount: 2
        )
        let (profileID, confidence) = CourseLeafLayoutClassifier.classify(domFeatures: features)
        XCTAssertEqual(profileID, CourseLeafLayoutProfileID.profileC.rawValue)
        XCTAssertGreaterThan(confidence, 0.5)
    }

    func testClassify_emptyFeatures_defaultsToProfileDefault() {
        let (profileID, _) = CourseLeafLayoutClassifier.classify(domFeatures: CatalogDOMFeatures())
        XCTAssertEqual(profileID, CourseLeafLayoutProfileID.profileDefault.rawValue)
    }

    /// School → expected profile mapping lives in tests only (not production classifier).
    func testFixtureSchoolVectors_mapToExpectedProfiles() {
        let nyu = CatalogDOMFeatures(detailCodeCount: 30, divCourseblockCount: 30, detailTitleCount: 30)
        XCTAssertEqual(
            CourseLeafLayoutClassifier.classify(domFeatures: nyu).0,
            CourseLeafLayoutProfileID.profileA.rawValue
        )

        let fordham = CatalogDOMFeatures(courseblocktitleCount: 20, divCourseblockCount: 20)
        XCTAssertEqual(
            CourseLeafLayoutClassifier.classify(domFeatures: fordham).0,
            CourseLeafLayoutProfileID.profileB.rawValue
        )

        let cmu = CatalogDOMFeatures(dlCourseblockCount: 12)
        XCTAssertEqual(
            CourseLeafLayoutClassifier.classify(domFeatures: cmu).0,
            CourseLeafLayoutProfileID.profileC.rawValue
        )
    }
}
