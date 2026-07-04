#if os(macOS)
import XCTest

/// Layer 1 — accessibility audits (before public launch).
final class AssistantAccessibilityUITests: CollegeUITestCase {

    func testAccessibility_composerAndSendLabeled() throws {
        launchAndOpenAssistant(fakeModel: true)
        let composer = composerField
        XCTAssertTrue(composer.waitForExistence(timeout: 15))
        XCTAssertTrue(composer.isHittable || composer.exists)
        let send = sendButton
        XCTAssertTrue(send.waitForExistence(timeout: 5))
        XCTAssertFalse(send.label.isEmpty)
    }

    func testAccessibility_sessionBadgeReadable() throws {
        launchAndOpenAssistant(fakeModel: true)
        assertSessionBadgeVisible()
        let badge = app.descendants(matching: .any)["assistant.sessionBadge"].firstMatch
        let label = badge.label + (badge.value as? String ?? "")
        XCTAssertTrue(label.localizedCaseInsensitiveContains("Talking to:"))
    }

    func testAccessibility_bubblesExistAfterTurn() throws {
        launchAndOpenAssistant(fakeModel: true, stubLocalLLM: true)
        focusComposerAndSend("Accessibility check")
        waitUntilAssistantIdle()
        XCTAssertGreaterThanOrEqual(assistantBubbleElements().count, 1)
        XCTAssertGreaterThanOrEqual(userBubbleElements().count, 1)
    }
}
#endif
