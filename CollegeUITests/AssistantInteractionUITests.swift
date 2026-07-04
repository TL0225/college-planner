#if os(macOS)
import XCTest

/// Layer 1 — interaction tests (confirm, feedback, pending actions).
final class AssistantInteractionUITests: CollegeUITestCase {

    func testStub_createTaskConfirmation() throws {
        launchAndOpenAssistant(fakeModel: true, stubLocalLLM: true)
        focusComposerAndSend("UITEST_CONFIRM create task for Friday")
        waitUntilAssistantIdle()
        let confirm = app.buttons["assistant.pendingAction.confirm"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 30))
        confirm.click()
        waitUntilAssistantIdle()
        XCTAssertGreaterThanOrEqual(assistantBubbleElements().count, 1)
    }

    func testFeedback_thumbsDownShowsToast() throws {
        launchAndOpenAssistant(fakeModel: true, stubLocalLLM: true)
        focusComposerAndSend("What model are you?")
        waitUntilAssistantIdle()
        tapFeedbackNotHelpful()
        waitForFeedbackToast()
    }

    func testPendingAction_cancelButtonExists() throws {
        launchAndOpenAssistant(fakeModel: true, stubLocalLLM: true)
        focusComposerAndSend("UITEST_CONFIRM create task for Friday")
        waitUntilAssistantIdle()
        let cancel = app.buttons["assistant.pendingAction.cancel"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 30))
    }
}
#endif
