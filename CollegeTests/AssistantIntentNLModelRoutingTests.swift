import XCTest
@testable import College

final class AssistantIntentNLModelRoutingTests: XCTestCase {

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: AssistantIntentNLModelSettings.enabledKey)
        UserDefaults.standard.removeObject(forKey: AssistantIntentNLModelSettings.probabilityThresholdKey)
        UserDefaults.standard.removeObject(forKey: AssistantIntentEmbeddingSettings.enabledKey)
        ProductionIntentClassifier.resetForTesting()
        super.tearDown()
    }

    /// Low threshold maximizes chance Create ML predicts the seeded training label (`fafsa_help`).
    func testSemanticsUsesNLModelWhenEmbeddingDisabled() throws {
        UserDefaults.standard.set(true, forKey: AssistantIntentNLModelSettings.enabledKey)
        UserDefaults.standard.set(0.08, forKey: AssistantIntentNLModelSettings.probabilityThresholdKey)
        UserDefaults.standard.set(false, forKey: AssistantIntentEmbeddingSettings.enabledKey)
        ProductionIntentClassifier.resetForTesting()

        let suggestion = AssistantIntentSemantics.classify(
            message: "when is the FAFSA filing deadline each year",
            role: .academicAdvisor
        )
        XCTAssertEqual(suggestion?.matchedIntent, "fafsa_help")
    }

    func testSemanticsFallsThroughToKeywordWhenEmbedAndNLInsufficient() throws {
        UserDefaults.standard.set(false, forKey: AssistantIntentNLModelSettings.enabledKey)
        UserDefaults.standard.set(false, forKey: AssistantIntentEmbeddingSettings.enabledKey)
        ProductionIntentClassifier.resetForTesting()

        let suggestion = AssistantIntentSemantics.classify(
            message: "fafsa deadlines for next semester",
            role: .academicAdvisor
        )
        XCTAssertEqual(suggestion?.matchedIntent, "fafsa_help")
    }
}
