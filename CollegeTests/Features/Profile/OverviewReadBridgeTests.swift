// OverviewReadBridgeTests.swift
// Feature: Profile
// Purpose: Profile module — OverviewReadBridgeTests.
// Data: CollegePersistence / repositories when applicable.

import CollegeCalendar
import SwiftData
import XCTest
@testable import College

@MainActor
final class OverviewReadBridgeTests: PersistenceTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        for task in try profileContext.fetch(FetchDescriptor<PlannerTask>()) {
            profileContext.delete(task)
        }
        for event in try profileContext.fetch(FetchDescriptor<CalendarEvent>()) {
            profileContext.delete(event)
        }
        for application in try profileContext.fetch(FetchDescriptor<JobApplication>()) {
            profileContext.delete(application)
        }
        for doc in try profileContext.fetch(FetchDescriptor<VaultDocument>()) {
            profileContext.delete(doc)
        }
        for academic in try profileContext.fetch(FetchDescriptor<AcademicProfile>()) {
            profileContext.delete(academic)
        }
        for profile in try profileContext.fetch(FetchDescriptor<Profile>()) {
            profileContext.delete(profile)
        }
        try profileContext.save()
    }

    func testPendingTasksFromStore() throws {
        let task = PlannerTask(
            title: "Overview Bridge Task",
            dueDate: Date().addingTimeInterval(86_400),
            isCompleted: false,
            priority: 0,
            createdAt: .now,
            lastUpdated: .now
        )
        profileContext.insert(task)
        try profileContext.save()

        let tasks = OverviewReadBridge.pendingTasks(limit: 5, collegePersistence: .shared)
        XCTAssertEqual(tasks.count, 1)
        XCTAssertEqual(tasks.first?.title, "Overview Bridge Task")
    }

    func testTodayEventSummariesFromStore() throws {
        let start = Calendar.current.startOfDay(for: Date()).addingTimeInterval(3600)
        _ = try CalendarRepository(context: profileContext).createCalendarEvent(
            title: "Overview Today Event",
            startDate: start,
            endDate: start.addingTimeInterval(3600),
            allDay: false
        )
        ModelMergeCoalescer.flushNow()

        let calendarManager = CalendarIntegrationManager()
        let events = OverviewReadBridge.todayEventSummaries(
            calendarManager: calendarManager,
            collegePersistence: .shared
        )
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.title, "Overview Today Event")
    }

    func testCareerFollowUpsFromStore() throws {
        _ = try CareerRepository(context: profileContext).addApplication(
            title: "Platform Engineer",
            company: "Bridge Labs",
            postingURLString: "",
            jobDescriptionText: "",
            interviewStatus: "",
            applicationDeadline: nil,
            status: .applied
        )
        ModelMergeCoalescer.flushNow()

        let followUps = OverviewReadBridge.careerFollowUps(limit: 3, collegePersistence: .shared)
        XCTAssertEqual(followUps.count, 1)
        XCTAssertEqual(followUps.first?.company, "Bridge Labs")
        XCTAssertEqual(followUps.first?.roleTitle, "Platform Engineer")
    }

    func testAcademicProfilesRead() throws {
        let profile = Profile(name: "Overview Test")
        profileContext.insert(profile)
        let academic = AcademicProfile(
            sortOrder: 0,
            isPrimary: true,
            isActive: true,
            status: AcademicProfileStatus.active.rawValue
        )
        academic.profile = profile
        profileContext.insert(academic)
        try profileContext.save()

        let profiles = OverviewReadBridge.academicProfiles(collegePersistence: .shared)
        XCTAssertFalse(profiles.isEmpty)
        XCTAssertTrue(try ProfileRepository(context: profileContext).hasMirroredAcademicProfileRows())
    }

    func testRecentDocumentsFromStore() throws {
        let document = VaultDocument(
            fileName: "OverviewBridge.pdf",
            category: "Syllabus",
            addedAt: Date(),
            localRelativePath: "vault/overview-bridge.pdf",
            isFolder: false
        )
        profileContext.insert(document)
        try profileContext.save()

        let docs = OverviewReadBridge.recentDocuments(limit: 3, collegePersistence: .shared)
        XCTAssertEqual(docs.count, 1)
        XCTAssertEqual(docs.first?.displayName, "OverviewBridge.pdf")
    }

    func testNextUpcomingEventFromStore() throws {
        let start = Date().addingTimeInterval(7200)
        _ = try CalendarRepository(context: profileContext).createCalendarEvent(
            title: "Overview Next Event",
            startDate: start,
            endDate: start.addingTimeInterval(3600),
            allDay: false
        )
        ModelMergeCoalescer.flushNow()

        let calendarManager = CalendarIntegrationManager()
        let next = OverviewReadBridge.nextUpcomingEvent(
            calendarManager: calendarManager,
            collegePersistence: .shared
        )
        XCTAssertEqual(next?.title, "Overview Next Event")
    }

    func testUpcomingEventSummariesFromStore() throws {
        let start = Calendar.current.startOfDay(for: Date()).addingTimeInterval(86_400 + 3600)
        _ = try CalendarRepository(context: profileContext).createCalendarEvent(
            title: "Future Event",
            startDate: start,
            endDate: start.addingTimeInterval(3600),
            allDay: false
        )
        ModelMergeCoalescer.flushNow()

        let calendarManager = CalendarIntegrationManager()
        let events = OverviewReadBridge.upcomingEventSummaries(
            days: 8,
            calendarManager: calendarManager,
            collegePersistence: .shared
        )
        XCTAssertFalse(events.isEmpty)
        XCTAssertTrue(events.contains { $0.title == "Future Event" })
    }
}
