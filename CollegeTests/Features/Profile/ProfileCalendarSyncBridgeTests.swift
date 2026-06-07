// ProfileCalendarSyncBridgeTests.swift
// Feature: Profile
// Purpose: Profile module — ProfileCalendarSyncBridgeTests.
// Data: CollegePersistence / repositories when applicable.

import SwiftData
import XCTest
@testable import College

@MainActor
final class ProfileCalendarSyncBridgeTests: PersistenceTestCase {
    func testCalendarEventAndTaskWrites() throws {
        let profileRepo = ProfileRepository(context: profileContext)
        let plan = try profileRepo.createPlan(
            name: "Plan",
            type: "Major",
            major: "CS",
            minor: "",
            concentration: ""
        )
        let semester = try profileRepo.createSemester(
            plan: plan,
            name: "Fall 2026",
            year: 2026,
            season: "Fall",
            seasonOrder: profileRepo.seasonOrder(for: "Fall")
        )

        let calendarRepo = CalendarRepository(context: profileContext)
        _ = try calendarRepo.createCalendarEvent(
            title: "CS Lecture",
            startDate: Date(timeIntervalSince1970: 1_700_000_000),
            endDate: Date(timeIntervalSince1970: 1_700_003_600),
            allDay: false,
            semester: semester,
            notes: "Room 101",
            location: "Engineering Hall"
        )
        _ = try calendarRepo.createPlannerTask(
            title: "Problem Set 1",
            dueDate: Date(timeIntervalSince1970: 1_700_086_400),
            semester: semester,
            priority: 1
        )
        ModelMergeCoalescer.flushNow()

        XCTAssertEqual(try calendarRepo.fetchEvents(from: .distantPast, to: .distantFuture, limit: 10).count, 1)
        XCTAssertEqual(try calendarRepo.fetchTasks(dueBefore: .distantFuture, limit: 10).count, 1)
        let hits = try calendarRepo.searchEvents(query: "Lecture", limit: 10)
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits.first?.location, "Engineering Hall")
    }

    func testDeleteCalendarEventRemovesStoreRow() throws {
        let calendarRepo = CalendarRepository(context: profileContext)
        let event = try calendarRepo.createCalendarEvent(
            title: "Temporary",
            startDate: .now,
            endDate: .now.addingTimeInterval(3600),
            allDay: false
        )
        ModelMergeCoalescer.flushNow()
        XCTAssertNotNil(try calendarRepo.fetchCalendarEvent(id: event.id))

        try calendarRepo.deleteCalendarEvent(id: event.id)
        ModelMergeCoalescer.flushNow()
        XCTAssertNil(try calendarRepo.fetchCalendarEvent(id: event.id))
    }

    func testCollegePersistenceDeleteCalendarEvent() throws {
        let eventID = CollegePersistence.shared.addCalendarEvent(
            title: "Temporary",
            startDate: .now,
            endDate: .now.addingTimeInterval(3600),
            allDay: false,
            semester: nil,
            course: nil
        )
        ModelMergeCoalescer.flushNow()
        XCTAssertNotNil(try CalendarRepository(context: profileContext).fetchCalendarEvent(id: eventID))

        CollegePersistence.shared.deleteCalendarEvent(id: eventID)
        ModelMergeCoalescer.flushNow()
        XCTAssertNil(try CalendarRepository(context: profileContext).fetchCalendarEvent(id: eventID))
    }
}

@MainActor
final class CalendarEventSearchBridgeTests: PersistenceTestCase {
    func testSearchUsesStoreEvents() throws {
        _ = try CalendarRepository(context: profileContext).createCalendarEvent(
            title: "Algorithms Midterm",
            startDate: Date(timeIntervalSince1970: 1_710_000_000),
            endDate: Date(timeIntervalSince1970: 1_710_003_600),
            allDay: false,
            location: "North Campus"
        )
        ModelMergeCoalescer.flushNow()

        let hits = CalendarEventSearchBridge.search(
            query: "Midterm",
            collegePersistence: .shared
        )
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits.first?.title, "Algorithms Midterm")
        XCTAssertEqual(hits.first?.location, "North Campus")
    }

    func testSearchRespectsLimit() throws {
        let repo = CalendarRepository(context: profileContext)
        for index in 0..<5 {
            _ = try repo.createCalendarEvent(
                title: "Match \(index)",
                startDate: Date(timeIntervalSince1970: 1_720_000_000 + Double(index)),
                endDate: Date(timeIntervalSince1970: 1_720_003_600 + Double(index)),
                allDay: false
            )
        }
        ModelMergeCoalescer.flushNow()

        let hits = CalendarEventSearchBridge.search(query: "Match", limit: 2, collegePersistence: .shared)
        XCTAssertEqual(hits.count, 2)
    }
}
