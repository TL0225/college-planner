// GlassToolbarAccessibilityTests.swift
// Feature: App / Toolbar
// Purpose: Accessibility contract for window toolbar controls.

import XCTest
@testable import College

@MainActor
final class GlassToolbarAccessibilityTests: XCTestCase {
    private let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // App
        .deletingLastPathComponent() // CollegeTests
        .deletingLastPathComponent() // repo root

    func testMinHitTargetMeetsAccessibilityFloor() {
        XCTAssertGreaterThanOrEqual(ToolbarMetrics.minHitTarget, 44)
    }

    func testCalendarToolbarChromeUsesStableIdentifiers() throws {
        let viewsFile = repoRoot.appendingPathComponent("College/App/Toolbar/AppToolbarViews.swift")
        let source = try String(contentsOf: viewsFile, encoding: .utf8)
        XCTAssertTrue(source.contains("toolbar.calendar.previous"))
        XCTAssertTrue(source.contains("toolbar.calendar.next"))
        XCTAssertTrue(source.contains("toolbar.calendar.sidebarToggle"))
    }

    func testAcademicsSidebarToggleDispatchesOnly() throws {
        let viewsFile = repoRoot.appendingPathComponent("College/App/Toolbar/AppToolbarViews.swift")
        let source = try String(contentsOf: viewsFile, encoding: .utf8)
        guard let range = source.range(of: "struct AcademicsToolbarSidebarToggleView") else {
            return XCTFail("Missing AcademicsToolbarSidebarToggleView")
        }
        let tail = source[range.lowerBound...]
        guard let endRange = tail.range(of: "struct AcademicsToolbarAddProfileButton") else {
            return XCTFail("Missing AcademicsToolbarAddProfileButton boundary")
        }
        let body = tail[..<endRange.lowerBound]
        XCTAssertTrue(body.contains("dispatcher.dispatch(.academics(.statsSidebarToggle))"))
        XCTAssertFalse(body.contains("statsSidebarShown.toggle()"))
    }
}
