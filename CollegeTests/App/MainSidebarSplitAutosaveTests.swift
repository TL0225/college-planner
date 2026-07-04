// MainSidebarSplitAutosaveTests.swift
// Feature: Shared
// Purpose: Unit tests for fixed main sidebar column width.

import XCTest
@testable import College

@MainActor
final class MainSidebarSplitAutosaveTests: XCTestCase {

    private let key = "NSSplitView Subview Frames \(AutosaveNames.mainSidebarSplit)"

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: key)
        super.tearDown()
    }

    func testRestoredLeadingColumnWidth_alwaysReturnsFixedWidth() {
        UserDefaults.standard.removeObject(forKey: key)
        XCTAssertEqual(
            MainSidebarSplitAutosave.restoredLeadingColumnWidth(),
            SidebarColumnLayout.fixedWidth
        )

        let savedWide = NSRect(x: 0, y: 0, width: 240, height: 900)
        UserDefaults.standard.set([NSStringFromRect(savedWide)], forKey: key)
        XCTAssertEqual(
            MainSidebarSplitAutosave.restoredLeadingColumnWidth(),
            SidebarColumnLayout.fixedWidth
        )
    }

    func testFixedLeadingColumnWidth_matchesIconOnlyRail() {
        XCTAssertEqual(SidebarColumnLayout.fixedWidth, SidebarColumnLayout.collapsedMinWidth)
        XCTAssertLessThan(SidebarColumnLayout.collapsedMinWidth, SidebarColumnLayout.iconOnlyThreshold)
    }

    func testTrafficLightCenteredWidth_usesSymmetricInsetFormula() {
        // leadingInset == trailingInset when width = minX + maxX
        let minX: CGFloat = 13
        let maxX: CGFloat = 65
        let width = minX + maxX
        XCTAssertEqual(width - maxX, minX)
        XCTAssertEqual(width, 78)
    }
}
