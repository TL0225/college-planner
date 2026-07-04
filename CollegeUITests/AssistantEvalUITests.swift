#if os(macOS)
import XCTest

/// Layer 5 — UI-recorded eval runs (auto-prompt, nightly).
final class AssistantEvalUITests: CollegeUITestCase {

    func testComprehensive_autoPromptScriptRunsAllQuestions() throws {
        let promptsPath = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/assistant-auto-prompts.txt")
            .path
        launchAndOpenAssistant(
            fakeModel: true,
            stubLocalLLM: true,
            seedMinimalPlanner: true,
            seedDeclaredMajor: true,
            autoPrompts: true,
            autoPromptsFile: promptsPath,
            streaming: false
        )
        waitForAutoPromptRun(expectedPromptCount: 10, timeout: 240)
        XCTAssertGreaterThanOrEqual(assistantBubbleElements().count, 10)
    }
}
#endif
