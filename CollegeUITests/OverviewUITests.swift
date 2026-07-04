#if os(macOS)
import XCTest

@MainActor
final class OverviewUITests: CollegeUITestCase {
    func testOverviewRootLoadsAfterSelectingDegreePage() {
        launchAppEnsuringAccessibility()
        XCTAssertTrue(openSidebarPage(linkID: "sidebar.link.degree", timeout: 20))

        let overview = app.descendants(matching: .any)["overview.root"].firstMatch
        XCTAssertTrue(
            overview.waitForExistence(timeout: 20),
            "Overview root should appear on the Degree page."
        )
    }
}
#endif
