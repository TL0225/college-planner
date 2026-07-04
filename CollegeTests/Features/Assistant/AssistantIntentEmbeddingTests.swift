// AssistantIntentEmbeddingTests.swift
import Foundation
import Testing
@testable import College

@Suite("Assistant Intent Embedding")
struct AssistantIntentEmbeddingTests {

    @Test("Classifier paraphrase maps to FAFSA intent")
    func classifierParaphraseMapsToFafsaIntent() {
        let hit = AssistantIntentEmbeddingClassifier.classify(
            message: "how do I complete the federal student aid application",
            threshold: 0.55,
            minimumIntentMargin: 0.01
        )
        #expect(hit?.intentId == "fafsa_help")
    }

    @Test("Classifier margin rejects ambiguous when scores too close")
    func classifierMarginRejectsAmbiguousWhenScoresTooClose() {
        let hit = AssistantIntentEmbeddingClassifier.classify(
            message: "x",
            threshold: 0.0,
            minimumIntentMargin: 1.0
        )
        #expect(hit == nil)
    }

    @Test("Keyword path still works when embedding disabled")
    func keywordPathStillWorksWhenEmbeddingDisabled() {
        defer {
            UserDefaults.standard.removeObject(forKey: AssistantIntentEmbeddingSettings.enabledKey)
        }
        UserDefaults.standard.set(false, forKey: AssistantIntentEmbeddingSettings.enabledKey)
        let hit = AssistantIntentSemantics.classify(message: "fafsa deadlines", role: .academicAdvisor)
        #expect(hit?.matchedIntent == "fafsa_help")
    }

    @Test("Semantics uses embedding when enabled and above threshold")
    func semanticsUsesEmbeddingWhenEnabledAndAboveThreshold() {
        defer {
            UserDefaults.standard.removeObject(forKey: AssistantIntentEmbeddingSettings.enabledKey)
            UserDefaults.standard.removeObject(forKey: AssistantIntentEmbeddingSettings.thresholdKey)
            UserDefaults.standard.removeObject(forKey: AssistantIntentEmbeddingSettings.marginKey)
        }
        UserDefaults.standard.set(true, forKey: AssistantIntentEmbeddingSettings.enabledKey)
        UserDefaults.standard.set(0.55, forKey: AssistantIntentEmbeddingSettings.thresholdKey)
        UserDefaults.standard.set(0.01, forKey: AssistantIntentEmbeddingSettings.marginKey)
        let msg = "how do I complete the federal student aid application"
        let suggestion = AssistantIntentSemantics.classify(message: msg, role: .academicAdvisor)
        #expect(suggestion?.matchedIntent == "fafsa_help")
    }

    @Test("Planning tool names matches descriptor names")
    @MainActor
    func planningToolNamesMatchesDescriptorNames() {
        let academic = AIAssistantToolRegistry.planningToolNames(for: .academicAdvisor)
        #expect(academic.contains("getStudentProfile"))
        #expect(academic.contains("draftSemesterPlan"))
        let financial = AIAssistantToolRegistry.planningToolNames(for: .financialAdvisor)
        #expect(financial.contains("getSAPStatus"))
    }
}
