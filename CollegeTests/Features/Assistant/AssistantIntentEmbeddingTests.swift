// AssistantIntentEmbeddingTests.swift
// Feature: Assistant
// Purpose: Assistant module — AssistantIntentEmbeddingTests.
// Data: CollegePersistence / repositories when applicable.

import XCTest
@testable import College

final class AssistantIntentEmbeddingTests: XCTestCase {

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: AssistantIntentEmbeddingSettings.enabledKey)
        UserDefaults.standard.removeObject(forKey: AssistantIntentEmbeddingSettings.thresholdKey)
        UserDefaults.standard.removeObject(forKey: AssistantIntentEmbeddingSettings.marginKey)
        super.tearDown()
    }

    func testClassifierParaphraseMapsToFafsaIntent() {
        let hit = AssistantIntentEmbeddingClassifier.classify(
            message: "how do I complete the federal student aid application",
            threshold: 0.55,
            minimumIntentMargin: 0.01
        )
        XCTAssertEqual(hit?.intentId, "fafsa_help")
    }

    func testClassifierMarginRejectsAmbiguousWhenScoresTooClose() {
        let hit = AssistantIntentEmbeddingClassifier.classify(
            message: "x",
            threshold: 0.0,
            minimumIntentMargin: 1.0
        )
        XCTAssertNil(hit)
    }

    func testKeywordPathStillWorksWhenEmbeddingDisabled() {
        UserDefaults.standard.set(false, forKey: AssistantIntentEmbeddingSettings.enabledKey)
        let hit = AssistantIntentSemantics.classify(message: "fafsa deadlines", role: .academicAdvisor)
        XCTAssertEqual(hit?.matchedIntent, "fafsa_help")
    }

    func testSemanticsUsesEmbeddingWhenEnabledAndAboveThreshold() {
        UserDefaults.standard.set(true, forKey: AssistantIntentEmbeddingSettings.enabledKey)
        UserDefaults.standard.set(0.55, forKey: AssistantIntentEmbeddingSettings.thresholdKey)
        UserDefaults.standard.set(0.01, forKey: AssistantIntentEmbeddingSettings.marginKey)
        let msg = "how do I complete the federal student aid application"
        let suggestion = AssistantIntentSemantics.classify(message: msg, role: .academicAdvisor)
        XCTAssertEqual(suggestion?.matchedIntent, "fafsa_help")
    }

    @MainActor
    func testPlanningToolNamesMatchesDescriptorNames() {
        let academic = AIAssistantToolRegistry.planningToolNames(for: .academicAdvisor)
        XCTAssertTrue(academic.contains("getStudentProfile"))
        XCTAssertTrue(academic.contains("draftSemesterPlan"))
        let financial = AIAssistantToolRegistry.planningToolNames(for: .financialAdvisor)
        XCTAssertTrue(financial.contains("getSAPStatus"))
    }
}
