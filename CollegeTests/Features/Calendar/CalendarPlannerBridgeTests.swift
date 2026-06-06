// CalendarPlannerBridgeTests.swift
// Feature: Calendar
// Purpose: Calendar module — CalendarPlannerBridgeTests.
// Data: CollegePersistence / repositories when applicable.

import CollegeCalendar
import SwiftData
import XCTest
@testable import College

@MainActor
final class CalendarPlannerBridgeTests: PersistenceTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        CalendarPersistenceAccess.writeRepository = CalendarWriteRepositoryPortAdapter(store: .shared)
        for task in try profileContext.fetch(FetchDescriptor<PlannerTask>()) {
            profileContext.delete(task)
        }
        try profileContext.save()
    }

    func testSidebarTasksPreferStoreMirror() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let sidebarDate = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        let due = sidebarDate.addingTimeInterval(14_400)
        let rangeEnd = sidebarDate.addingTimeInterval(86_400 * 7)

        let swiftTask = PlannerTask(
            title: "Sidebar Task",
            dueDate: due,
            isCompleted: false,
            priority: 0,
            createdAt: .now,
            lastUpdated: .now
        )
        profileContext.insert(swiftTask)
        try profileContext.save()

        let summaries = CalendarPlannerBridge.sidebarTasks(
            sidebarDate: sidebarDate,
            rangeStart: sidebarDate,
            rangeEnd: rangeEnd,
            calendar: calendar
        )
        XCTAssertEqual(summaries.count, 1)
        XCTAssertEqual(summaries.first?.title, "Sidebar Task")
    }

    func testSidebarTasksExcludeOtherDays() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let sidebarDate = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        let otherDay = calendar.date(byAdding: .day, value: 1, to: sidebarDate)!
        let rangeEnd = sidebarDate.addingTimeInterval(86_400 * 7)

        let repo = CalendarRepository(context: profileContext)
        _ = try repo.createPlannerTask(
            title: "Today",
            dueDate: sidebarDate.addingTimeInterval(3600)
        )
        _ = try repo.createPlannerTask(
            title: "Tomorrow",
            dueDate: otherDay.addingTimeInterval(3600)
        )
        ModelMergeCoalescer.flushNow()

        let summaries = CalendarPlannerBridge.sidebarTasks(
            sidebarDate: sidebarDate,
            rangeStart: sidebarDate,
            rangeEnd: rangeEnd,
            calendar: calendar
        )
        XCTAssertEqual(summaries.count, 1)
        XCTAssertEqual(summaries.first?.title, "Today")
    }
}
