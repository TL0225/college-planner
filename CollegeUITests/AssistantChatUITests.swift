#if os(macOS)
import XCTest

/// Layer 1 — chat UI only (~8 tests). No answer-quality assertions.
final class AssistantChatUITests: CollegeUITestCase {

    func testShell_opensAssistantWithStudentGuide() throws {
        applyAssistantHarness(app, fakeModel: true)
        launchAppEnsuringAccessibility()
        XCTAssertTrue(openAssistantFromSidebar(timeout: 30))
        let composer = composerField
        XCTAssertTrue(composer.waitForExistence(timeout: 25))
        assertStudentGuideVisible()
        assertSessionBadgeVisible()
    }

    func testShell_composerSendRoundTrip() throws {
        launchAndOpenAssistant(fakeModel: true, stubLocalLLM: true, seedMinimalPlanner: true)
        focusComposerAndSend("Hello assistant")
        waitUntilAssistantIdle()
        XCTAssertGreaterThanOrEqual(userBubbleElements().count, 1)
        XCTAssertGreaterThanOrEqual(assistantBubbleElements().count, 1)
    }

    func testTranscript_userAndAssistantBubblesAccumulate() throws {
        launchAndOpenAssistant(fakeModel: true, stubLocalLLM: true, seedMinimalPlanner: true)
        focusComposerAndSend("First message")
        waitUntilAssistantIdle()
        focusComposerAndSend("Second message")
        waitUntilAssistantIdle()
        XCTAssertGreaterThanOrEqual(userBubbleElements().count, 2)
        XCTAssertGreaterThanOrEqual(assistantBubbleElements().count, 2)
    }

    func testComposer_emptySendDisabled() throws {
        launchAndOpenAssistant(fakeModel: true)
        let composer = composerField
        XCTAssertTrue(composer.waitForExistence(timeout: 10))
        composer.click()
        composer.typeKey("a", modifierFlags: .command)
        composer.typeKey(.delete, modifierFlags: [])
        usleep(100_000)
        let send = sendButton
        XCTAssertTrue(send.waitForExistence(timeout: 5))
        XCTAssertFalse(send.isEnabled)
    }

    func testComposer_longMessageDoesNotBreakLayout() throws {
        launchAndOpenAssistant(fakeModel: true, stubLocalLLM: true)
        let long = String(repeating: "Plan my courses. ", count: 40)
        focusComposerAndSend(long)
        waitUntilAssistantIdle()
        XCTAssertGreaterThanOrEqual(assistantBubbleElements().count, 1)
    }

    func testComposer_pasteIntoField() throws {
        launchAndOpenAssistant(fakeModel: true, stubLocalLLM: true)
        focusComposerAndSend("Pasted prompt check")
        waitUntilAssistantIdle()
        XCTAssertGreaterThanOrEqual(userBubbleElements().count, 1)
    }

    func testLoading_sendReEnablesAfterReply() throws {
        launchAndOpenAssistant(fakeModel: true, stubLocalLLM: true)
        focusComposerAndSend("Quick question")
        waitUntilAssistantIdle()
        XCTAssertTrue(sendButton.isEnabled)
    }

    func testMarkdown_assistantBubbleExistsAfterReply() throws {
        launchAndOpenAssistant(fakeModel: true, stubLocalLLM: true, seedDeclaredMajor: true)
        focusComposerAndSend("What career does my major lead to?")
        waitUntilAssistantIdle()
        let text = lastAssistantBubbleText()
        XCTAssertFalse(text.isEmpty)
    }
}
#endif
