// CalendarSearchStoreTests.swift
// Feature: Calendar
// Purpose: Calendar module — CalendarSearchStoreTests.
// Data: CollegePersistence / repositories when applicable.

import SwiftData
import XCTest
@testable import College

@MainActor
final class CalendarSearchStoreTests: PersistenceTestCase {
    func testSearchOffMain_findsMatchingEvent() async throws {
        let semester = PlannerSemester(name: "Fall 2026", year: 2026, season: "Fall", seasonOrder: 1)
        profileContext.insert(semester)
        let event = CalendarEvent(
            title: "Linear Algebra Lecture",
            startDate: Date(timeIntervalSince1970: 1_900_000_000),
            endDate: Date(timeIntervalSince1970: 1_900_003_600),
            allDay: false
        )
        event.semester = semester
        profileContext.insert(event)
        try profileContext.save()

        let hits = await CalendarEventSearchBridge.searchOffMain(
            query: "Linear",
            semester: semester,
            limit: 10
        )
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits.first?.title, "Linear Algebra Lecture")
    }
}
