// AssistantIntentNLModelRoutingTests.swift
// NL model routing (Swift Testing).

import Foundation
import Testing
@testable import College

@Suite("Assistant Intent NL Model Routing")
struct AssistantIntentNLModelRoutingTests {

    @Test("Semantics uses NL model when embedding disabled")
    func semanticsUsesNLModelWhenEmbeddingDisabled() throws {
        defer { AssistantTestFixtures.resetIntentClassifierDefaults() }
        UserDefaults.standard.set(true, forKey: AssistantIntentNLModelSettings.enabledKey)
        UserDefaults.standard.set(0.08, forKey: AssistantIntentNLModelSettings.probabilityThresholdKey)
        UserDefaults.standard.set(false, forKey: AssistantIntentEmbeddingSettings.enabledKey)
        ProductionIntentClassifier.resetForTesting()

        // Hosted CI / some runners cannot load the bundled Create ML model.
        guard ProductionIntentClassifier.classify(message: "fafsa deadline") != nil else {
            return
        }

        let suggestion = AssistantIntentSemantics.classify(
            message: "when is the FAFSA filing deadline each year",
            role: .academicAdvisor
        )
        #expect(suggestion?.matchedIntent == "fafsa_help")
    }

    @Test("Semantics falls through to keyword when embed and NL insufficient")
    func semanticsFallsThroughToKeywordWhenEmbedAndNLInsufficient() throws {
        defer { AssistantTestFixtures.resetIntentClassifierDefaults() }
        UserDefaults.standard.set(false, forKey: AssistantIntentNLModelSettings.enabledKey)
        UserDefaults.standard.set(false, forKey: AssistantIntentEmbeddingSettings.enabledKey)
        ProductionIntentClassifier.resetForTesting()

        let suggestion = AssistantIntentSemantics.classify(
            message: "fafsa deadlines for next semester",
            role: .academicAdvisor
        )
        #expect(suggestion?.matchedIntent == "fafsa_help")
    }
}
