#if os(macOS)
import XCTest

/// One smoke navigation test per primary `AppPage` sidebar destination (M30-070).
@MainActor
final class AppPageNavigationUITests: CollegeUITestCase {
    func testDegreePageLoads() {
        assertPageLoads(linkID: "sidebar.link.degree", landmark: "overview.root")
    }

    func testAcademicsPageLoads() {
        assertPageLoads(linkID: "sidebar.link.academics", landmark: "shell.mainContent")
    }

    func testTransferPageLoads() {
        assertPageLoads(linkID: "sidebar.link.transferDatabase", landmark: "shell.mainContent")
    }

    func testCalendarPageLoads() {
        assertPageLoads(linkID: "sidebar.link.calendar", landmark: "shell.mainContent")
    }

    func testCareerPageLoads() {
        assertPageLoads(linkID: "sidebar.link.career", landmark: "shell.mainContent")
    }

    func testAssistantPageLoads() {
        applyAssistantHarness(app, fakeModel: true)
        launchAppEnsuringAccessibility()
        XCTAssertTrue(openSidebarPage(linkID: "sidebar.link.assistant", timeout: 30))
        XCTAssertTrue(composerField.waitForExistence(timeout: 45))
    }

    func testDocumentsPageLoads() {
        assertPageLoads(linkID: "sidebar.link.documents", landmark: "shell.mainContent")
    }

    func testLMSPageLoads() {
        assertPageLoads(linkID: "sidebar.link.lms", landmark: "shell.mainContent")
    }

    func testProfilePageLoads() {
        assertPageLoads(linkID: "sidebar.link.profile", landmark: "shell.mainContent")
    }

    func testSettingsLinkVisible() {
        launchAppEnsuringAccessibility()
        let link = app.descendants(matching: .any)["sidebar.link.settings"].firstMatch
        XCTAssertTrue(link.waitForExistence(timeout: 30))
    }

    func testAssistantEmptyGuideVisible() {
        applyAssistantHarness(app, fakeModel: true)
        launchAppEnsuringAccessibility()
        XCTAssertTrue(openSidebarPage(linkID: "sidebar.link.assistant", timeout: 30))
        let guide = app.descendants(matching: .any)["assistant.studentGuidePanel"].firstMatch
        XCTAssertTrue(guide.waitForExistence(timeout: 45))
    }

    #if DEBUG
    func testDebugPageLoads() {
        assertPageLoads(linkID: "sidebar.link.debug", landmark: "shell.mainContent")
    }
    #endif

    private func assertPageLoads(linkID: String, landmark: String) {
        launchAppEnsuringAccessibility()
        XCTAssertTrue(openSidebarPage(linkID: linkID, timeout: 30), "Missing sidebar link \(linkID)")

        let element = app.descendants(matching: .any)[landmark].firstMatch
        XCTAssertTrue(
            element.waitForExistence(timeout: 45),
            "Expected landmark \(landmark) for \(linkID)"
        )
    }
}
#endif
