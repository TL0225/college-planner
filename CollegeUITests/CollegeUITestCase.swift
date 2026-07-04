#if os(macOS)
import AppKit
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

    /// Ends orphaned app instances that block XCTest automation injection.
    private func terminateStaleCollegeInstances() {
        let bundleID = "Timothy.College"
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        guard !running.isEmpty else { return }
        for instance in running {
            instance.terminate()
        }
        usleep(400_000)
        for instance in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) {
            instance.forceTerminate()
        }
        usleep(300_000)
    }

    func applyBaseLaunchConfiguration(_ application: XCUIApplication) {
        application.launchArguments.append("--ui-test-boot-main")
        application.launchEnvironment["COLLEGE_UI_TEST_BOOT_MAIN"] = "1"
        application.launchArguments.append("--uitest-assistant-inference-stub")
        application.launchEnvironment["COLLEGE_UITEST_ASSISTANT_INFERENCE_STUB"] = "1"
        application.launchEnvironment["COLLEGE_UITEST_ASSISTANT_INFERENCE_BACKEND"] = "stub"
    }

    /// Full assistant harness: reach chat without Gemma; optional MLX JSON stub and planner seed data.
    func applyAssistantHarness(
        _ application: XCUIApplication,
        fakeModel: Bool = true,
        stubLocalLLM: Bool = false,
        seedMinimalPlanner: Bool = false,
        seedDeclaredMajor: Bool = false,
        stubWebSearch: Bool = false,
        autoPrompts: Bool = false,
        autoPromptsFile: String? = nil,
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
        if seedDeclaredMajor {
            application.launchArguments.append("--uitest-seed-declared-major")
            application.launchEnvironment["COLLEGE_UITEST_SEED_DECLARED_MAJOR"] = "1"
        }
        if stubWebSearch {
            application.launchArguments.append("--uitest-stub-web-search")
            application.launchEnvironment["COLLEGE_UITEST_STUB_WEB_SEARCH"] = "1"
        }
        if autoPrompts {
            application.launchArguments.append("--uitest-assistant-auto-prompts")
        }
        if let autoPromptsFile {
            application.launchArguments.append("--uitest-assistant-auto-prompts-file=\(autoPromptsFile)")
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
        seedMinimalPlanner: Bool = false,
        seedDeclaredMajor: Bool = false,
        stubWebSearch: Bool = false,
        autoPrompts: Bool = false,
        autoPromptsFile: String? = nil,
        streaming: Bool? = false
    ) {
        applyAssistantHarness(
            app,
            fakeModel: fakeModel,
            stubLocalLLM: stubLocalLLM,
            seedMinimalPlanner: seedMinimalPlanner,
            seedDeclaredMajor: seedDeclaredMajor,
            stubWebSearch: stubWebSearch,
            autoPrompts: autoPrompts,
            autoPromptsFile: autoPromptsFile,
            streaming: streaming
        )
        launchAppEnsuringAccessibility()

        if !openAssistantFromSidebar(timeout: 30) {
            XCTFail("Failed to open Assistant via sidebar controls.")
        }

        let composer = composerField
        XCTAssertTrue(composer.waitForExistence(timeout: 25))
    }

    var composerField: XCUIElement {
        let id = "assistant.composerField"
        let asTextField = app.textFields[id].firstMatch
        if asTextField.exists { return asTextField }
        return app.textViews[id].firstMatch
    }

    func focusComposerAndSend(_ text: String) {
        app.activate()
        let composer = composerField
        XCTAssertTrue(composer.waitForExistence(timeout: 15))
        XCTAssertTrue(composer.isEnabled)

        composer.click()
        usleep(150_000)

        // Select-all + paste is more reliable than typeText on macOS NSViewRepresentable fields.
        composer.typeKey("a", modifierFlags: .command)
        usleep(50_000)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        composer.typeKey("v", modifierFlags: .command)
        usleep(100_000)

        let current = (composer.value as? String ?? composer.label).trimmingCharacters(in: .whitespacesAndNewlines)
        if current.isEmpty || !current.localizedCaseInsensitiveContains(String(text.prefix(min(12, text.count)))) {
            composer.click()
            composer.typeText(text)
        }

        let send = sendButton
        XCTAssertTrue(send.waitForExistence(timeout: 5))
        let sendDeadline = Date().addingTimeInterval(10)
        while Date() < sendDeadline, !send.isEnabled {
            usleep(50_000)
        }
        XCTAssertTrue(send.isEnabled, "Send stayed disabled after entering: \(text.prefix(40))")
        send.click()
    }

    /// Waits until the in-app auto-prompt runner finishes (user bubbles match expected count).
    func waitForAutoPromptRun(expectedPromptCount: Int, timeout: TimeInterval = 180) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let userCount = userBubbleElements().count
            if userCount >= expectedPromptCount, !isResponding {
                return
            }
            usleep(200_000)
        }
        XCTFail("Auto-prompt run did not finish (\(userBubbleElements().count)/\(expectedPromptCount) user bubbles)")
    }

    var isResponding: Bool {
        let send = sendButton
        return send.exists && !send.isEnabled
    }

    var sendButton: XCUIElement {
        app.descendants(matching: .any)["assistant.sendButton"].firstMatch
    }

    func waitUntilAssistantIdle(timeout: TimeInterval = 90) {
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

    func assistantBubbleElements() -> XCUIElementQuery {
        app.staticTexts.matching(identifier: "assistant.bubble.assistant")
    }

    func userBubbleElements() -> XCUIElementQuery {
        app.staticTexts.matching(identifier: "assistant.bubble.user")
    }

    func lastAssistantBubbleText(timeout: TimeInterval = 10) -> String {
        let bubbles = assistantBubbleElements()
        XCTAssertGreaterThan(bubbles.count, 0)
        let last = bubbles.element(boundBy: bubbles.count - 1)
        XCTAssertTrue(last.waitForExistence(timeout: timeout))
        return normalizedBubbleText(last)
    }

    func assistantBubbleText(at index: Int) -> String {
        let bubbles = assistantBubbleElements()
        XCTAssertLessThan(index, bubbles.count)
        return normalizedBubbleText(bubbles.element(boundBy: index))
    }

    func assertLastAssistantReplyContains(
        _ substring: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let text = lastAssistantBubbleText()
        XCTAssertTrue(
            text.localizedCaseInsensitiveContains(substring),
            "Expected assistant reply to contain \"\(substring)\". Got: \(text)",
            file: file,
            line: line
        )
    }

    func assertLastAssistantReplyExcludes(
        _ substring: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let text = lastAssistantBubbleText()
        XCTAssertFalse(
            text.localizedCaseInsensitiveContains(substring),
            "Expected assistant reply to exclude \"\(substring)\". Got: \(text)",
            file: file,
            line: line
        )
    }

    func assertStudentGuideVisible(file: StaticString = #filePath, line: UInt = #line) {
        let guide = app.descendants(matching: .any)["assistant.studentGuidePanel"].firstMatch
        if guide.waitForExistence(timeout: 8) { return }
        // Guide appears only on an empty transcript; fall back to composer + session badge.
        assertSessionBadgeVisible(file: file, line: line)
        XCTAssertTrue(composerField.waitForExistence(timeout: 5), file: file, line: line)
    }

    func assertSessionBadgeVisible(file: StaticString = #filePath, line: UInt = #line) {
        let badge = app.descendants(matching: .any)["assistant.sessionBadge"].firstMatch
        XCTAssertTrue(badge.waitForExistence(timeout: 5), file: file, line: line)
        let label = badge.label + (badge.value as? String ?? "")
        XCTAssertTrue(label.localizedCaseInsensitiveContains("Talking to:"), "Unexpected badge: \(label)", file: file, line: line)
    }

    func tapFeedbackNotHelpful() {
        let button = app.descendants(matching: .any)["assistant.feedback.notHelpful"].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.click()
    }

    func waitForFeedbackToast(timeout: TimeInterval = 5) {
        let toast = app.descendants(matching: .any)["assistant.toast.feedbackSaved"].firstMatch
        XCTAssertTrue(toast.waitForExistence(timeout: timeout))
    }

    private func normalizedBubbleText(_ element: XCUIElement) -> String {
        (element.value as? String ?? element.label).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func activateMainWindowIfNeeded() {
        _ = app.wait(for: .runningForeground, timeout: 15)
        if app.state == .runningForeground || app.state == .runningBackground {
            app.activate()
        }
    }

    func launchAppEnsuringAccessibility(maxAttempts: Int = 3) {
        terminateStaleCollegeInstances()
        var launched = false
        for attempt in 1...maxAttempts {
            if app.state != .notRunning {
                app.terminate()
                _ = app.wait(for: .notRunning, timeout: 10)
            }
            app.launch()
            _ = app.wait(for: .runningForeground, timeout: 20)
            activateMainWindowIfNeeded()

            let deadline = Date().addingTimeInterval(45)
            while Date() < deadline {
                if app.windows.firstMatch.exists { launched = true; break }
                if app.descendants(matching: .any)["sidebar.link.assistant"].firstMatch.exists { launched = true; break }
                usleep(100_000)
            }
            if launched { break }
            if attempt < maxAttempts { usleep(800_000) }
        }
        XCTAssertTrue(launched, "App window did not appear for UI testing.")
    }

    @discardableResult
    func openSidebarPage(linkID: String, timeout: TimeInterval) -> Bool {
        let link = app.descendants(matching: .any)[linkID].firstMatch
        if link.waitForExistence(timeout: timeout) {
            link.click()
            return true
        }
        return false
    }

    @discardableResult
    func openAssistantFromSidebar(timeout: TimeInterval) -> Bool {
        let assistantID = app.descendants(matching: .any)["sidebar.link.assistant"].firstMatch
        if assistantID.waitForExistence(timeout: timeout) {
            assistantID.click()
            return true
        }

        let labelMatch = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label ==[c] %@", "Assistant"))
            .firstMatch
        if labelMatch.waitForExistence(timeout: 5) {
            labelMatch.click()
            return true
        }
        return false
    }
}
#endif
