// SettingsSessionControllerTests.swift
// Feature: Settings
// Purpose: Navigation history, pane restore, and window chrome for standalone Settings.

import XCTest
@testable import College

@MainActor
final class SettingsSessionControllerTests: XCTestCase {
    private let lastSectionKey = "settings.lastSelectedSection"

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: lastSectionKey)
        super.tearDown()
    }

    func testAlwaysOpensToProfileRegardlessOfStoredSection() {
        UserDefaults.standard.set(SettingsNavSection.calendar.rawValue, forKey: lastSectionKey)
        let session = SettingsSessionController()
        XCTAssertEqual(session.selectedSection, .profile)
        XCTAssertEqual(session.listSelection, .profile)
        XCTAssertEqual(session.history, [.profile])
    }

    func testSelectSectionUpdatesHistoryAndPersistence() {
        let session = SettingsSessionController()
        session.selectSection(.assistant)
        session.selectSection(.privacyAndData)

        XCTAssertEqual(session.selectedSection, .privacyAndData)
        XCTAssertEqual(session.history, [.profile, .assistant, .privacyAndData])
        XCTAssertEqual(session.historyIndex, 2)
        XCTAssertEqual(
            UserDefaults.standard.string(forKey: lastSectionKey),
            SettingsNavSection.privacyAndData.rawValue
        )
    }

    func testBackAndForwardNavigation() {
        let session = SettingsSessionController()
        session.selectSection(.calendar)
        session.selectSection(.career)

        XCTAssertTrue(session.canGoBack)
        XCTAssertFalse(session.canGoForward)

        session.goBack()
        XCTAssertEqual(session.selectedSection, .calendar)
        XCTAssertTrue(session.canGoForward)

        session.goForward()
        XCTAssertEqual(session.selectedSection, .career)
    }

    func testForwardHistoryTruncatesOnNewSelection() {
        let session = SettingsSessionController()
        session.selectSection(.calendar)
        session.selectSection(.career)
        session.goBack()
        session.selectSection(.documents)

        XCTAssertEqual(session.history, [.profile, .calendar, .documents])
        XCTAssertEqual(session.selectedSection, .documents)
        XCTAssertFalse(session.canGoForward)
    }

    func testWindowTitleReflectsSelectedPane() {
        let session = SettingsSessionController()
        session.selectSection(.academics)
        session.refreshChrome()
        XCTAssertEqual(session.selectedSection.displayName, SettingsNavSection.academics.displayName)
    }
}
