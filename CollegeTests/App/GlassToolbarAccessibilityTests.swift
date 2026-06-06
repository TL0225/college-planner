// GlassToolbarAccessibilityTests.swift
// Feature: App / Toolbar / Glass
// Purpose: Accessibility contract for public glass controls.

import XCTest
@testable import College

@MainActor
final class GlassToolbarAccessibilityTests: XCTestCase {
    private let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // App
        .deletingLastPathComponent() // CollegeTests
        .deletingLastPathComponent() // repo root

    func testMinHitTargetMeetsAccessibilityFloor() {
        let theme = TahoeGlassStyle().theme
        XCTAssertGreaterThanOrEqual(theme.minHitTarget, 44)
    }

    func testPublicGlassControlsDeclareAccessibilityLabels() throws {
        let controlsFile = repoRoot
            .appendingPathComponent("College/App/Toolbar/Glass/GlassToolbarControls.swift")
        let source = try String(contentsOf: controlsFile, encoding: .utf8)

        let publicControls = [
            "StaticToolbarGlassButton",
            "GlassToolbarCircleButton",
            "GlassSearchFieldView",
            "GlassToolbarAddMenuButton",
            "GlassToolbarProfileAvatarButton",
        ]

        for control in publicControls {
            guard let range = source.range(of: "struct \(control)") else {
                XCTFail("Missing public control \(control)")
                continue
            }
            let tail = source[range.lowerBound...]
            guard let bodyRange = tail.range(of: "var body: some View") else {
                XCTFail("Missing body for \(control)")
                continue
            }
            let body = tail[bodyRange.lowerBound...].prefix(3_000)
            XCTAssertTrue(
                body.contains(".accessibilityLabel"),
                "\(control) must declare accessibilityLabel"
            )
            XCTAssertTrue(
                body.contains(".accessibilityIdentifier") || body.contains("accessibilityIdentifier:"),
                "\(control) must declare accessibilityIdentifier"
            )
            XCTAssertTrue(
                body.contains("minHitTarget"),
                "\(control) must honor theme.minHitTarget"
            )
        }
    }

    func testCalendarToolbarChromeUsesStableIdentifiers() throws {
        let viewsFile = repoRoot.appendingPathComponent("College/App/Toolbar/AppToolbarViews.swift")
        let source = try String(contentsOf: viewsFile, encoding: .utf8)
        XCTAssertTrue(source.contains("toolbar.calendar.previous"))
        XCTAssertTrue(source.contains("toolbar.calendar.next"))
        XCTAssertTrue(source.contains("toolbar.calendar.sidebarToggle"))
    }
}
