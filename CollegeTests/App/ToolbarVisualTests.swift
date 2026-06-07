// ToolbarVisualTests.swift
// Feature: App / Toolbar
// Purpose: Liquid Glass toolbar visual regression snapshots.

import CollegeCalendar
import SwiftUI
import XCTest
@testable import College

@MainActor
final class ToolbarVisualTests: XCTestCase {
    private let renderSize = CGSize(width: 520, height: 56)

    private func calendarChrome(colorScheme: ColorScheme = .light) -> some View {
        let scene = CalendarSceneState()
        scene.headerDate = "June 2026"
        scene.viewMode = .month
        scene.sidebarShown = true
        let container = AppContainer(
            telemetry: NoOpToolbarTelemetry(),
            calendarScene: scene
        )

        return CalToolbarChromeView(
            dispatcher: container.toolbarDispatcher,
            calendarScene: scene
        )
        .environment(\.colorScheme, colorScheme)
    }

    func testCalendarToolbarLightMode() throws {
        try ToolbarSnapshotHarness.assertSnapshot(named: "calendar-light-regular", size: renderSize) {
            calendarChrome(colorScheme: .light)
        }
    }

    func testCalendarToolbarDarkMode() throws {
        try ToolbarSnapshotHarness.assertSnapshot(
            named: "calendar-dark-regular",
            size: renderSize,
            colorScheme: .dark
        ) {
            calendarChrome(colorScheme: .dark)
        }
    }
}
