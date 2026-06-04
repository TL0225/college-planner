// CalendarReadBridgeTests.swift
// Feature: Calendar
// Purpose: Calendar module — CalendarReadBridgeTests.
// Data: CollegePersistence / repositories when applicable.

import SwiftData
import XCTest
@testable import College

@MainActor
final class CalendarReadBridgeTests: PersistenceTestCase {
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
        ProfilePlannerSyncBridge.resetSyncTokenForTesting()
    }

    func testEventSnapshotsPreferStoreMirror() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let end = start.addingTimeInterval(86_400 * 7)
        let calendarRepo = CalendarRepository(context: profileContext)
        _ = try calendarRepo.createCalendarEvent(
            title: "local store Cache Event",
            startDate: start.addingTimeInterval(3600),
            endDate: start.addingTimeInterval(7200),
            allDay: false
        )
        ModelMergeCoalescer.flushNow()
        XCTAssertEqual(
            try calendarRepo.fetchEventsOverlapping(start: start, end: end, limit: 10).count,
            1
        )

        let calendarManager = CalendarIntegrationManager()
        calendarManager.enabledCalendarIDs.insert("Apple:Home")
        if let swiftEvent = try calendarRepo.fetchEventsOverlapping(start: start, end: end, limit: 1).first {
            XCTAssertTrue(calendarManager.shouldDisplayEvent(swiftEvent))
        }
        let snapshots = CalendarReadBridge.eventSnapshots(
            rangeStart: start,
            rangeEnd: end,
            calendarManager: calendarManager,
            collegePersistence: .shared
        )
        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(snapshots.first?.title, "local store Cache Event")
    }

    func testTaskSnapshotsFromStoreMirror() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let end = start.addingTimeInterval(86_400 * 7)
        _ = try CalendarRepository(context: profileContext).createPlannerTask(
            title: "Read Chapter 3",
            dueDate: start.addingTimeInterval(43_200)
        )
        ModelMergeCoalescer.flushNow()

        let snapshots = CalendarReadBridge.taskSnapshots(rangeStart: start, rangeEnd: end)
        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(snapshots.first?.title, "Read Chapter 3")
    }

    func testEventSnapshotsFromStoreWrites() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let end = start.addingTimeInterval(86_400 * 7)
        _ = try CalendarRepository(context: profileContext).createCalendarEvent(
            title: "local store Event",
            startDate: start.addingTimeInterval(3600),
            endDate: start.addingTimeInterval(7200),
            allDay: false,
            semester: nil,
            course: nil
        )
        ModelMergeCoalescer.flushNow()

        let calendarManager = CalendarIntegrationManager()
        let snapshots = CalendarReadBridge.eventSnapshots(
            rangeStart: start,
            rangeEnd: end,
            calendarManager: calendarManager,
            collegePersistence: .shared
        )
        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(snapshots.first?.title, "local store Event")
    }

    func testEventSnapshotsRespectShouldDisplayEventFilter() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let end = start.addingTimeInterval(86_400 * 7)
        _ = try CalendarRepository(context: profileContext).createCalendarEvent(
            title: "Hidden Event",
            startDate: start.addingTimeInterval(3600),
            endDate: start.addingTimeInterval(7200),
            allDay: false,
            semester: nil,
            course: nil
        )
        ModelMergeCoalescer.flushNow()

        let calendarManager = CalendarIntegrationManager()
        calendarManager.enabledCalendarIDs.remove("Apple:Home")

        let snapshots = CalendarReadBridge.eventSnapshots(
            rangeStart: start,
            rangeEnd: end,
            calendarManager: calendarManager,
            collegePersistence: .shared
        )
        XCTAssertTrue(snapshots.isEmpty)
    }

    func testOverlapFetchReturnsIntersectingEvents() throws {
        let ctx = try XCTUnwrap(profileContext)
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let end = start.addingTimeInterval(86_400)
        let event = CalendarEvent(
            title: "Overlap",
            startDate: start.addingTimeInterval(-3600),
            endDate: start.addingTimeInterval(3600)
        )
        ctx.insert(event)
        try ctx.save()

        let repo = CalendarRepository(context: ctx)
        let fetched = try repo.fetchEventsOverlapping(start: start, end: end, limit: 10)
        XCTAssertEqual(fetched.count, 1)
    }
}
