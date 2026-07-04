// CalendarModalCoordinatorIntegrationTests.swift
// Feature: Calendar / App shell
// Purpose: Calendar modal coordinator round-trip through ModalCoordinator (M30-069).

import XCTest
@testable import College

@MainActor
final class CalendarModalCoordinatorIntegrationTests: XCTestCase {
    func testCalendarAdapter_presentsAddAndEditCalendarItems() {
        let modal = ModalCoordinator()
        let adapter = ModalCoordinatorCalendarAdapter(coordinator: modal)

        XCTAssertFalse(adapter.isAddCalendarItemPresented)
        XCTAssertFalse(adapter.isEditCalendarItemPresented)

        let semesterID = UUID()
        adapter.presentAddCalendarItem(
            semesterID: semesterID,
            title: "Study session",
            start: Date(timeIntervalSince1970: 1_700_000_000),
            end: Date(timeIntervalSince1970: 1_700_003_600)
        )

        XCTAssertTrue(adapter.isAddCalendarItemPresented)
        XCTAssertEqual(adapter.addCalendarItemSemesterID, semesterID)
        XCTAssertEqual(adapter.addCalendarItemInitialTitle, "Study session")
        XCTAssertNotNil(adapter.addCalendarItemInitialStart)
        XCTAssertNotNil(adapter.addCalendarItemInitialEnd)

        adapter.isAddCalendarItemPresented = false
        XCTAssertNil(modal.activeModal)

        let eventID = UUID()
        adapter.presentEditCalendarItem(eventID: eventID)
        XCTAssertTrue(adapter.isEditCalendarItemPresented)
        XCTAssertEqual(adapter.editCalendarItemID, eventID)

        adapter.presentAddTask(semesterID: semesterID, prefillCourseID: nil)
        if case .addTask(let resolvedSemester, let courseID) = modal.activeModal {
            XCTAssertEqual(resolvedSemester, semesterID)
            XCTAssertNil(courseID)
        } else {
            XCTFail("Expected addTask modal")
        }
    }

    func testCalendarAdapter_searchInspectorFlagsStayIndependent() {
        let modal = ModalCoordinator()
        let adapter = ModalCoordinatorCalendarAdapter(coordinator: modal)

        adapter.presentAddCatalogCourse(semesterID: UUID())
        if case .addCatalogCourse = modal.activeModal {
            XCTAssertFalse(adapter.isAddCalendarItemPresented)
        } else {
            XCTFail("Expected catalog course modal")
        }
    }
}
