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
        let chromeFile = repoRoot.appendingPathComponent("College/App/Toolbar/AppToolbarViews.swift")
        let chromeSource = try String(contentsOf: chromeFile, encoding: .utf8)
        XCTAssertTrue(chromeSource.contains("toolbar.calendar.previous"))
        XCTAssertTrue(chromeSource.contains("toolbar.calendar.next"))
        XCTAssertTrue(chromeSource.contains("toolbar.calendar.sidebarToggle"))

        let calendarToolbarFile = repoRoot.appendingPathComponent("College/App/Toolbar/CalendarToolbarContent.swift")
        let calendarToolbarSource = try String(contentsOf: calendarToolbarFile, encoding: .utf8)
        XCTAssertTrue(
            calendarToolbarSource.contains("cal.inspectorToggle"),
            "Expected calendar inspector toggle in main window toolbar"
        )
        XCTAssertTrue(
            calendarToolbarSource.contains(".sharedBackgroundVisibility(.hidden)"),
            "Calendar toolbar items should hide glass circles"
        )

        let calendarViewFile = repoRoot.appendingPathComponent("Packages/CollegeCalendar/Sources/CollegeCalendar/UI/CalendarView.swift")
        let calendarViewSource = try String(contentsOf: calendarViewFile, encoding: .utf8)
        XCTAssertFalse(
            calendarViewSource.contains("calendar.inspectorToggle"),
            "Calendar inspector toggle belongs in CalendarToolbarContent, not CalendarView"
        )
    }

    func testAcademicsSidebarToggleDispatchesOnly() throws {
        let viewsFile = repoRoot.appendingPathComponent("College/App/Toolbar/AppToolbarViews.swift")
        let source = try String(contentsOf: viewsFile, encoding: .utf8)
        guard let range = source.range(of: "struct AcademicsToolbarSidebarToggleView") else {
            return XCTFail("Missing AcademicsToolbarSidebarToggleView")
        }
        let tail = source[range.lowerBound...]
        guard let endRange = tail.range(of: "struct AcademicsDegreeScopeToolbar") else {
            return XCTFail("Missing AcademicsDegreeScopeToolbar boundary")
        }
        let body = tail[..<endRange.lowerBound]
        XCTAssertTrue(body.contains("isInspectorPresented.toggle()"))
        XCTAssertFalse(body.contains("statsSidebarShown.toggle()"))
    }

    func testFeatureToolbarProvidersExposeAccessibilityIdentifiers() throws {
        let expectations: [(file: String, identifiers: [String])] = [
            ("College/App/Toolbar/AcademicsToolbarContent.swift", ["toolbar.academics.addCourse"]),
            ("College/App/Toolbar/AssistantToolbarContent.swift", [
                "toolbar.assistant.webMemory",
                "toolbar.assistant.more",
            ]),
            ("College/App/Toolbar/ProfileToolbarContent.swift", [
                "toolbar.profile.advisorPrep",
                "toolbar.profile.edit",
            ]),
            ("College/App/Toolbar/CareerToolbarContent.swift", [
                "toolbar.career.copyMarkdown",
                "toolbar.career.add",
            ]),
            ("College/App/Toolbar/WebToolbarContent.swift", [
                "toolbar.web.back",
                "toolbar.web.forward",
                "toolbar.web.reload",
                "toolbar.web.find",
                "toolbar.web.portalHome",
            ]),
            ("College/App/Toolbar/ToolbarProviding.swift", [
                "toolbar.transfer.refresh",
                "toolbar.transfer.import",
                "toolbar.transfer.addManual",
                "toolbar.transfer.share",
                "toolbar.transfer.toggleMode",
            ]),
        ]

        for expectation in expectations {
            let url = repoRoot.appendingPathComponent(expectation.file)
            let source = try String(contentsOf: url, encoding: .utf8)
            for identifier in expectation.identifiers {
                XCTAssertTrue(
                    source.contains(identifier),
                    "Expected \(identifier) in \(expectation.file)"
                )
            }
        }
    }

    func testShellLandmarksAreDeclaredInContentView() throws {
        let contentView = repoRoot.appendingPathComponent("College/App/ContentView.swift")
        let source = try String(contentsOf: contentView, encoding: .utf8)
        XCTAssertTrue(source.contains("accessibilityLabel(\"Sidebar navigation\")"))
        XCTAssertTrue(source.contains("accessibilityLabel(\"Main content\")"))
        XCTAssertTrue(source.contains("accessibilityIdentifier(\"shell.mainContent\")"))
    }

    func testSheetDismissModifierHandlesEscapeKey() throws {
        let sheetDismiss = repoRoot.appendingPathComponent("College/Core/SheetDismissOnOutsideClick.swift")
        let source = try String(contentsOf: sheetDismiss, encoding: .utf8)
        XCTAssertTrue(source.contains("installEscapeMonitorIfNeeded"))
        XCTAssertTrue(source.contains("event.keyCode == 53"))
    }

    func testOnboardingExposesStepAccessibilityIdentifiers() throws {
        let onboarding = repoRoot.appendingPathComponent("College/App/OnboardingRootView.swift")
        let source = try String(contentsOf: onboarding, encoding: .utf8)
        XCTAssertTrue(source.contains("accessibilityIdentifier(\"onboarding.root\")"))
        XCTAssertTrue(source.contains("accessibilityIdentifier(\"onboarding.step."))
        XCTAssertTrue(source.contains("accessibilityIdentifier(\"onboarding.continue\")"))
    }

    func testDiagnosticsHelpMenuAvailableInRelease() throws {
        let compatibility = repoRoot.appendingPathComponent("College/App/AppCompatibility.swift")
        let source = try String(contentsOf: compatibility, encoding: .utf8)
        XCTAssertTrue(source.contains("Button(\"Diagnostics…\")"))
        XCTAssertFalse(source.contains("#if DEBUG\n            Button(\"Diagnostics"))
    }

    func testPreservedPagesSupportDynamicType() throws {
        let support = repoRoot.appendingPathComponent("College/Core/DesignSystem/ShellDynamicTypeSupport.swift")
        let source = try String(contentsOf: support, encoding: .utf8)
        XCTAssertTrue(source.contains("shellDynamicTypeReadable"))
        XCTAssertTrue(source.contains("accessibility3"))
    }
}
