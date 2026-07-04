#if os(macOS)
import XCTest

/// Legacy entry point — tests moved to AssistantChatUITests, AssistantInteractionUITests,
/// AssistantAccessibilityUITests, and AssistantEvalUITests (Layer 1/5 split).
final class AssistantUITests: CollegeUITestCase {
    func testLegacySuite_redirectsToSplitTargets() throws {
        // Keeps scheme discovery stable; real coverage lives in split UI test types.
        XCTAssertTrue(true)
    }
}
#endif
