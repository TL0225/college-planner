#if os(macOS)
import XCTest

/// Shared launch configuration for College UI tests.
class CollegeUITestCase: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
        app = XCUIApplication()
        applyBaseLaunchConfiguration(app)
    }

    func applyBaseLaunchConfiguration(_ application: XCUIApplication) {
        application.launchArguments.append("--ui-test-boot-main")
        application.launchEnvironment["COLLEGE_UI_TEST_BOOT_MAIN"] = "1"
    }

    /// Full assistant harness: reach chat without Gemma; optional MLX JSON stub and planner seed data.
    func applyAssistantHarness(
        _ application: XCUIApplication,
        fakeModel: Bool = true,
        stubLocalLLM: Bool = false,
        seedMinimalPlanner: Bool = false,
        diagnostics: Bool = false,
        lengthPreset: String? = nil,
        streaming: Bool? = nil
    ) {
        if fakeModel {
            application.launchArguments.append("--uitest-fake-assistant-model")
            application.launchEnvironment["COLLEGE_UITEST_FAKE_ASSISTANT_MODEL"] = "1"
        }
        if stubLocalLLM {
            application.launchArguments.append("--uitest-local-llm-stub")
            application.launchEnvironment["COLLEGE_UITEST_LOCAL_LLM_STUB"] = "1"
        }
        if seedMinimalPlanner {
            application.launchArguments.append("--uitest-seed-minimal-planner")
            application.launchEnvironment["COLLEGE_UITEST_SEED_PLANNER"] = "1"
        }
        if diagnostics {
            application.launchArguments.append("--uitest-assistant-diagnostics=1")
            application.launchEnvironment["COLLEGE_UITEST_ASSISTANT_DIAGNOSTICS"] = "1"
        }
        if let lengthPreset {
            application.launchArguments.append("--uitest-assistant-length-preset=\(lengthPreset)")
            application.launchEnvironment["COLLEGE_UITEST_ASSISTANT_LENGTH_PRESET"] = lengthPreset
        }
        if let streaming {
            application.launchArguments.append("--uitest-assistant-streaming=\(streaming ? "1" : "0")")
            application.launchEnvironment["COLLEGE_UITEST_ASSISTANT_STREAMING"] = streaming ? "1" : "0"
        }
    }

    func launchAndOpenAssistant(
        fakeModel: Bool = true,
        stubLocalLLM: Bool = false,
        seedMinimalPlanner: Bool = false
    ) {
        applyAssistantHarness(
            app,
            fakeModel: fakeModel,
            stubLocalLLM: stubLocalLLM,
            seedMinimalPlanner: seedMinimalPlanner
        )
        app.launch()
        activateMainWindowIfNeeded()

        let assistantLink = app.descendants(matching: .any)["sidebar.link.assistant"].firstMatch
        XCTAssertTrue(assistantLink.waitForExistence(timeout: 30))
        assistantLink.click()

        let composer = composerField
        XCTAssertTrue(composer.waitForExistence(timeout: 25))
    }

    private var composerField: XCUIElement {
        let id = "assistant.composerField"
        let asTextField = app.textFields[id].firstMatch
        if asTextField.exists { return asTextField }
        return app.textViews[id].firstMatch
    }

    func focusComposerAndSend(_ text: String) {
        let composer = composerField
        XCTAssertTrue(composer.waitForExistence(timeout: 10))
        composer.click()
        composer.typeText(text)

        let send = sendButton
        XCTAssertTrue(send.waitForExistence(timeout: 5))
        XCTAssertTrue(send.isEnabled)
        send.click()
    }

    /// Send control (may not appear under `XCUIElementTypeButton` while disabled on macOS).
    private var sendButton: XCUIElement {
        app.descendants(matching: .any)["assistant.sendButton"].firstMatch
    }

    /// `isResponding` disables send; on macOS disabled controls are often omitted from `app.buttons`, so poll `descendants` until enabled.
    func waitUntilAssistantIdle(timeout: TimeInterval = 60) {
        let send = sendButton
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if send.exists && send.isEnabled {
                return
            }
            usleep(50_000)
        }
        XCTFail("Assistant send control did not become enabled within \(timeout) seconds")
    }

    func lastAssistantBubbleText(timeout: TimeInterval = 5) -> String {
        let bubbles = app.staticTexts.matching(identifier: "assistant.bubble.assistant")
        XCTAssertGreaterThan(bubbles.count, 0)
        let last = bubbles.element(boundBy: bubbles.count - 1)
        XCTAssertTrue(last.waitForExistence(timeout: timeout))
        return last.value as? String ?? last.label
    }

    private func activateMainWindowIfNeeded() {
        // Xcode UI tests on macOS sometimes need a moment for the shell window.
        _ = app.wait(for: .runningForeground, timeout: 15)
    }
}
#endif
