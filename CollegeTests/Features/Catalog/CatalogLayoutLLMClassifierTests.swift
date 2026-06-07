// CatalogLayoutLLMClassifierTests.swift
// Feature: Shared
// Purpose: Ambiguity gating for layout LLM fallback (no model invocation).
// Data: CollegePersistence / repositories when applicable.

import XCTest
@testable import College

final class CatalogLayoutLLMClassifierTests: XCTestCase {
    func testShouldUseLLM_lowConfidence() {
        XCTAssertTrue(CatalogLayoutLLMClassifier.shouldUseLLM(0.4, scores: [0.9, 0.1]))
    }

    func testShouldUseLLM_tightMargin() {
        XCTAssertTrue(CatalogLayoutLLMClassifier.shouldUseLLM(0.7, scores: [0.72, 0.68, 0.1]))
    }

    func testShouldUseLLM_clearWinner() {
        XCTAssertFalse(CatalogLayoutLLMClassifier.shouldUseLLM(0.85, scores: [0.9, 0.2, 0.1]))
    }

    func testCourseLeafScorecard_matchesDeterministicClassifier() {
        let features = CatalogDOMFeatures(
            detailCodeCount: 20,
            courseblocktitleCount: 0,
            divCourseblockCount: 20,
            dlCourseblockCount: 0,
            scCourselistCount: 0,
            detailTitleCount: 20
        )
        let expected = CourseLeafLayoutClassifier.classify(domFeatures: features)
        let scorecard = CatalogLayoutLLMClassifier.courseLeafScorecard(domFeatures: features)
        XCTAssertEqual(scorecard.profileID, expected.0)
        XCTAssertEqual(scorecard.confidence, expected.1, accuracy: 0.001)
    }
}
