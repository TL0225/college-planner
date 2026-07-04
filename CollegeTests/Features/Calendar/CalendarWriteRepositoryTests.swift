// CalendarWriteRepositoryTests.swift
// Feature: Calendar
// Purpose: Calendar module — CalendarWriteRepositoryTests.
// Data: CollegePersistence / repositories when applicable.

import SwiftData
import XCTest
@testable import College

@MainActor
final class CalendarWriteRepositoryTests: PersistenceTestCase {
    private var persistence: CollegePersistence { .shared }

    override func setUpWithError() throws {
        try super.setUpWithError()
        let ctx = AppDataStore.shared.profileContext
        for event in try ctx.fetch(FetchDescriptor<CalendarEvent>()) {
            ctx.delete(event)
        }
        for task in try ctx.fetch(FetchDescriptor<PlannerTask>()) {
            ctx.delete(task)
        }
        try ctx.save()
    }

    func testUpsertAndDeleteCalendarEvent() throws {
        let start = Date(timeIntervalSince1970: 1_710_000_000)
        let end = start.addingTimeInterval(3600)

        let eventID = persistence.addCalendarEvent(
            title: "Office Hours",
            startDate: start,
            endDate: end,
            allDay: false,
            semester: nil,
            course: nil,
            notes: "Bring questions",
            location: "Room 101"
        )

        let repo = CalendarRepository(context: AppDataStore.shared.profileContext)
        XCTAssertEqual(try repo.fetchCalendarEvent(id: eventID)?.title, "Office Hours")
        XCTAssertEqual(try repo.fetchCalendarEvent(id: eventID)?.location, "Room 101")

        try repo.deleteCalendarEvent(id: eventID)
        ModelMergeCoalescer.flushNow()
        XCTAssertNil(try repo.fetchCalendarEvent(id: eventID))
    }

    func testUpsertUpdateAndDeletePlannerTask() throws {
        let due = Date(timeIntervalSince1970: 1_710_086_400)

        let taskID = persistence.addTask(
            title: "Problem Set 3",
            dueDate: due,
            semester: nil,
            course: nil
        )

        let repo = CalendarRepository(context: AppDataStore.shared.profileContext)
        XCTAssertEqual(try repo.fetchPlannerTask(id: taskID)?.title, "Problem Set 3")
        XCTAssertEqual(try repo.fetchPlannerTask(id: taskID)?.isCompleted, false)

        persistence.setTaskCompleted(id: taskID, completed: true)
        XCTAssertEqual(try repo.fetchPlannerTask(id: taskID)?.isCompleted, true)

        try repo.deletePlannerTask(id: taskID)
        ModelMergeCoalescer.flushNow()
        XCTAssertNil(try repo.fetchPlannerTask(id: taskID))
    }

    func testUpdateCalendarEventDetails() throws {
        let start = Date(timeIntervalSince1970: 1_721_000_000)
        let end = start.addingTimeInterval(3600)
        let eventID = persistence.addCalendarEvent(
            title: "Lecture",
            startDate: start,
            endDate: end,
            allDay: false,
            semester: nil,
            course: nil,
            notes: "Chapter 1",
            location: "Hall A"
        )

        persistence.updateCalendarEvent(
            id: eventID,
            title: "Lecture (Updated)",
            startDate: start,
            endDate: end,
            allDay: false,
            semester: nil,
            course: nil,
            notes: "Chapter 2",
            location: "Hall B"
        )

        let mirrored = try CalendarRepository(context: AppDataStore.shared.profileContext).fetchCalendarEvent(id: eventID)
        XCTAssertEqual(mirrored?.title, "Lecture (Updated)")
        XCTAssertEqual(mirrored?.notes, "Chapter 2")
        XCTAssertEqual(mirrored?.location, "Hall B")
    }

    func testUpdateTaskWritesStore() throws {
        let due = Date(timeIntervalSince1970: 1_710_172_800)
        let taskID = persistence.addTask(
            title: "Essay Draft",
            dueDate: due,
            semester: nil,
            course: nil
        )

        let newDue = due.addingTimeInterval(86_400)
        persistence.updateTask(
            id: taskID,
            title: "Essay Final",
            dueDate: newDue,
            semester: nil,
            course: nil,
            notes: "Submit online"
        )

        let mirrored = try CalendarRepository(context: AppDataStore.shared.profileContext).fetchPlannerTask(id: taskID)
        XCTAssertEqual(mirrored?.title, "Essay Final")
        XCTAssertEqual(mirrored?.dueDate, newDue)
        XCTAssertEqual(mirrored?.notes, "Submit online")
    }

    func testUpdateCalendarEventTimes() throws {
        let start = Date(timeIntervalSince1970: 1_720_000_000)
        let end = start.addingTimeInterval(1800)
        let eventID = persistence.addCalendarEvent(
            title: "Study Block",
            startDate: start,
            endDate: end,
            allDay: false,
            semester: nil,
            course: nil
        )

        let newStart = start.addingTimeInterval(7200)
        let newEnd = end.addingTimeInterval(7200)
        persistence.updateCalendarEventTimes(id: eventID, startDate: newStart, endDate: newEnd)

        let mirrored = try CalendarRepository(context: AppDataStore.shared.profileContext).fetchCalendarEvent(id: eventID)
        XCTAssertEqual(mirrored?.startDate, newStart)
        XCTAssertEqual(mirrored?.endDate, newEnd)
    }
}
