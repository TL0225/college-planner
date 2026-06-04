#if os(macOS)
import XCTest

/// AI Assistant coverage: Tier1 deterministic router + Tier2 stubbed planning/tools.
///
/// Requires macOS host with Xcode. Does **not** download Gemma when launch flags below are used.
final class AssistantUITests: CollegeUITestCase {

    func testTier1_opensAssistantWithFakeModel() throws {
        applyAssistantHarness(app, fakeModel: true, stubLocalLLM: false, seedMinimalPlanner: false)
        launchAppEnsuringAccessibility()

        XCTAssertTrue(openAssistantFromSidebar(timeout: 30))

        let composerTF = app.textFields["assistant.composerField"].firstMatch
        let composerTV = app.textViews["assistant.composerField"].firstMatch
        XCTAssertTrue(composerTF.waitForExistence(timeout: 5) || composerTV.waitForExistence(timeout: 25))
    }

    func testTier1_deterministicWeekAgenda() throws {
        launchAndOpenAssistant(fakeModel: true, stubLocalLLM: true, seedMinimalPlanner: true)
        focusComposerAndSend(AssistantScenarioCatalog.tier1WeekAgenda)
        waitUntilAssistantIdle()
        let text = lastAssistantBubbleText()
        XCTAssertTrue(
            text.contains("Upcoming 7-day snapshot:") || text.contains("No upcoming events"),
            "Unexpected agenda text: \(text)"
        )
    }

    func testTier1_deterministicDueItems() throws {
        launchAndOpenAssistant(fakeModel: true, stubLocalLLM: true, seedMinimalPlanner: true)
        focusComposerAndSend(AssistantScenarioCatalog.tier1DueItems)
        waitUntilAssistantIdle()
        let text = lastAssistantBubbleText()
        XCTAssertTrue(
            text.contains("Open due items:") || text.contains("don't see any open tasks"),
            "Unexpected due-items text: \(text)"
        )
    }

    func testTier1_deterministicTomorrow() throws {
        launchAndOpenAssistant(fakeModel: true, stubLocalLLM: true, seedMinimalPlanner: true)
        focusComposerAndSend(AssistantScenarioCatalog.tier1Tomorrow)
        waitUntilAssistantIdle()
        let text = lastAssistantBubbleText()
        XCTAssertTrue(
            text.contains("Tomorrow's agenda:") || text.contains("clear for tomorrow") || text.contains("clear in your planner"),
            "Unexpected tomorrow text: \(text)"
        )
    }

    func testTier1_modelIdentity() throws {
        launchAndOpenAssistant(fakeModel: true, stubLocalLLM: true, seedMinimalPlanner: false)
        focusComposerAndSend(AssistantScenarioCatalog.tier1ModelIdentity)
        waitUntilAssistantIdle()
        let text = lastAssistantBubbleText()
        XCTAssertTrue(text.contains("Gemma") || text.contains("local"), "Unexpected identity text: \(text)")
    }

    func testTier2_stubProgramProgressMultiHop() throws {
        launchAndOpenAssistant(fakeModel: true, stubLocalLLM: true, seedMinimalPlanner: true)
        focusComposerAndSend(AssistantScenarioCatalog.tier2ProgramProgress)
        waitUntilAssistantIdle()
        let text = lastAssistantBubbleText()
        XCTAssertTrue(
            text.localizedCaseInsensitiveContains("stub summary") || text.localizedCaseInsensitiveContains("credits"),
            "Expected stub/tool-grounded answer, got: \(text)"
        )
    }

    func testTier2_createTaskConfirmation() throws {
        launchAndOpenAssistant(fakeModel: true, stubLocalLLM: true, seedMinimalPlanner: false)
        focusComposerAndSend(AssistantScenarioCatalog.tier2CreateTaskConfirm)
        waitUntilAssistantIdle()

        let confirm = app.buttons["assistant.pendingAction.confirm"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 30))
        confirm.click()

        waitUntilAssistantIdle()
        let text = lastAssistantBubbleText()
        XCTAssertTrue(text.contains("Confirmed") && text.contains("UITest Seeded Task"), text)
    }
}
#endif
