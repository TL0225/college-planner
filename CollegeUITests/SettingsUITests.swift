#if os(macOS)
import XCTest

/// Smoke tests for Settings layout and navigation.
final class SettingsUITests: CollegeUITestCase {

    func testOpensStandaloneSettingsFromFooter() throws {
        launchAppEnsuringAccessibility()
        app.typeKey(",", modifierFlags: .command)

        let connectedApps = app.staticTexts["Connected Apps"].firstMatch
        XCTAssertTrue(connectedApps.waitForExistence(timeout: 15))
    }

    func testSettingsSidebarShowsConnectedAppsLabel() throws {
        launchAppEnsuringAccessibility()
        app.typeKey(",", modifierFlags: .command)

        let connectedApps = app.staticTexts["Connected Apps"].firstMatch
        XCTAssertTrue(connectedApps.waitForExistence(timeout: 15))
        XCTAssertFalse(connectedApps.label.contains("…"))
    }

}
#endif
