// CalendarEventCRUDFlowTests.swift
// Snow Leopard flow #4: calendar event create → update → delete.

import SwiftData
import XCTest
@testable import College

@MainActor
final class CalendarEventCRUDFlowTests: PersistenceTestCase {
    func testEventCreateUpdateDeleteRoundTrip() throws {
        let persistence = CollegePersistence.shared
        let start = Date(timeIntervalSince1970: 1_730_000_000)
        let end = start.addingTimeInterval(3600)

        let eventID = persistence.addCalendarEvent(
            title: "Flow Lecture",
            startDate: start,
            endDate: end,
            allDay: false,
            semester: nil,
            course: nil,
            notes: "v1",
            location: "Hall A"
        )

        persistence.updateCalendarEvent(
            id: eventID,
            title: "Flow Lecture (Updated)",
            startDate: start,
            endDate: end,
            allDay: false,
            semester: nil,
            course: nil,
            notes: "v2",
            location: "Hall B"
        )

        let repo = CalendarRepository(context: AppDataStore.shared.profileContext)
        let updated = try repo.fetchCalendarEvent(id: eventID)
        XCTAssertEqual(updated?.title, "Flow Lecture (Updated)")
        XCTAssertEqual(updated?.location, "Hall B")

        try repo.deleteCalendarEvent(id: eventID)
        ModelMergeCoalescer.flushNow()
        XCTAssertNil(try repo.fetchCalendarEvent(id: eventID))
    }
}
