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

    private func calendarChrome(
        density: ToolbarDensity,
        colorScheme: ColorScheme = .light
    ) -> some View {
        let scene = CalendarSceneState()
        scene.headerDate = "June 2026"
        scene.viewMode = .month
        scene.sidebarShown = density == .expanded
        let container = AppContainer(
            telemetry: NoOpToolbarTelemetry(),
            calendarScene: scene
        )

        return CalToolbarChromeView()
            .environment(container)
            .glassToolbarEnvironment(density: density)
            .environment(\.colorScheme, colorScheme)
    }

    func testCalendarToolbarLightMode() throws {
        try ToolbarSnapshotHarness.assertSnapshot(named: "calendar-light-regular", size: renderSize) {
            calendarChrome(density: .regular, colorScheme: .light)
        }
    }

    func testCalendarToolbarDarkMode() throws {
        try ToolbarSnapshotHarness.assertSnapshot(
            named: "calendar-dark-regular",
            size: renderSize,
            colorScheme: .dark
        ) {
            calendarChrome(density: .regular, colorScheme: .dark)
        }
    }

    func testCalendarToolbarSidebarExpanded() throws {
        try ToolbarSnapshotHarness.assertSnapshot(named: "calendar-light-expanded", size: renderSize) {
            calendarChrome(density: .expanded, colorScheme: .light)
        }
    }

    func testCalendarToolbarSidebarCompact() throws {
        try ToolbarSnapshotHarness.assertSnapshot(named: "calendar-light-compact", size: renderSize) {
            calendarChrome(density: .compact, colorScheme: .light)
        }
    }

    func testGlassButtonDisabledState() throws {
        try ToolbarSnapshotHarness.assertSnapshot(named: "glass-button-disabled", size: CGSize(width: 64, height: 64)) {
            StaticToolbarGlassButton(
                symbol: "chevron.left",
                tip: "Previous",
                accessibilityIdentifier: "toolbar.test.previous",
                action: {},
                isEnabled: false
            )
            .glassToolbarEnvironment(density: .regular)
        }
    }

    func testGlassSearchFieldExpanded() throws {
        try ToolbarSnapshotHarness.assertSnapshot(named: "glass-search-expanded", size: CGSize(width: 280, height: 44)) {
            GlassSearchFieldView(text: .constant(""), placeholder: "Search events")
                .glassToolbarEnvironment(density: .expanded)
        }
    }

    func testGlassAddMenuCompact() throws {
        try ToolbarSnapshotHarness.assertSnapshot(named: "glass-add-menu-compact", size: CGSize(width: 64, height: 64)) {
            GlassToolbarAddMenuButton(onAddSemester: {}, onAddCourse: {})
                .glassToolbarEnvironment(density: .compact)
        }
    }

    func testGlassProfileAvatarExpanded() throws {
        try ToolbarSnapshotHarness.assertSnapshot(named: "glass-profile-expanded", size: CGSize(width: 64, height: 64)) {
            GlassToolbarProfileAvatarButton(initials: "TL", action: {})
                .glassToolbarEnvironment(density: .expanded)
        }
    }
}
