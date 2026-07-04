#if os(macOS)
import XCTest

/// Smoke tests for Settings layout and navigation.
final class SettingsUITests: CollegeUITestCase {

    func testOpensStandaloneSettingsFromFooter() throws {
        launchAppEnsuringAccessibility()
        app.typeKey(",", modifierFlags: .command)

        let profileSection = app.descendants(matching: .any)
            .matching(identifier: "settings.section.profile")
            .firstMatch
        XCTAssertTrue(profileSection.waitForExistence(timeout: 15))
    }

    func testSettingsSidebarShowsProfileSection() throws {
        launchAppEnsuringAccessibility()
        app.typeKey(",", modifierFlags: .command)

        let profileSection = app.descendants(matching: .any)
            .matching(identifier: "settings.section.profile")
            .firstMatch
        XCTAssertTrue(profileSection.waitForExistence(timeout: 15))
        XCTAssertFalse(profileSection.label.contains("…"))
    }

}
#endif
