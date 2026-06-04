// ProfilePartitionEntitySmokeTests.swift
// Feature: Profile
// Purpose: Profile module — ProfilePartitionEntitySmokeTests.
// Data: CollegePersistence / repositories when applicable.

import SwiftData
import XCTest
@testable import College

/// Inserts and fetches one row per profile-partition `@Model` not covered by planner tests (Phase 7g).
final class ProfilePartitionEntitySmokeTests: PersistenceTestCase {
    func testCalendarPlannerAndGradingModelsRoundTrip() throws {
        let ids = try PersistenceFixtureFactory.seedMinimalPlanner(in: profileContext)
        guard let semester = try ProfileRepository(context: profileContext).fetchSemester(id: ids.semesterID),
              let course = try ProfileRepository(context: profileContext).fetchCourse(id: ids.courseID) else {
            return XCTFail("Missing planner seed")
        }

        let category = CourseGradingCategory(name: "Exams", weightPercent: 40)
        category.course = course
        profileContext.insert(category)

        let event = CalendarEvent(
            title: "Midterm",
            startDate: .now,
            endDate: .now.addingTimeInterval(3600)
        )
        event.semester = semester
        event.course = course
        profileContext.insert(event)

        let task = PlannerTask(title: "Problem Set 1", dueDate: .now.addingTimeInterval(86_400))
        task.semester = semester
        task.course = course
        task.gradingCategory = category
        profileContext.insert(task)

        try profileContext.save()

        XCTAssertEqual(try profileContext.fetchCount(FetchDescriptor<CourseGradingCategory>()), 1)
        XCTAssertEqual(try profileContext.fetchCount(FetchDescriptor<CalendarEvent>()), 1)
        XCTAssertEqual(try profileContext.fetchCount(FetchDescriptor<PlannerTask>()), 1)
    }

    func testProfileExperienceAchievementRoundTrip() throws {
        let profile = Profile(name: "Alex")
        let experience = Experience(isCurrent: true)
        experience.title = "Intern"
        experience.company = "Acme"
        let achievement = Achievement()
        achievement.name = "Dean's List"
        experience.profile = profile
        achievement.profile = profile
        profile.experiences = [experience]
        profile.achievements = [achievement]

        profileContext.insert(profile)
        try profileContext.save()

        let fetched = try profileContext.fetch(FetchDescriptor<Profile>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.experiences?.count, 1)
        XCTAssertEqual(fetched.first?.achievements?.count, 1)
    }

    func testVaultAndWatchedFolderRoundTrip() throws {
        let folder = VaultDocument(
            fileName: "Syllabi",
            localRelativePath: "vault/syllabi",
            isFolder: true
        )
        let doc = VaultDocument(
            fileName: "syllabus.pdf",
            category: "Syllabus",
            localRelativePath: "vault/syllabi/syllabus.pdf"
        )
        doc.parentFolder = folder
        folder.children = [doc]

        let watched = WatchedFolder(path: "/Users/test/Documents")

        profileContext.insert(folder)
        profileContext.insert(watched)
        try profileContext.save()

        XCTAssertEqual(try profileContext.fetchCount(FetchDescriptor<VaultDocument>()), 2)
        XCTAssertEqual(try profileContext.fetchCount(FetchDescriptor<WatchedFolder>()), 1)
    }

    func testCareerModelsRoundTrip() throws {
        let resume = VaultDocument(
            fileName: "resume.pdf",
            localRelativePath: "vault/resume.pdf"
        )
        let posting = WorkdayJobPosting(companySlug: "acme", externalId: "JR123")
        posting.title = "Engineer"
        let application = JobApplication(statusRaw: "applied", sortOrder: 1)
        application.submittedResume = resume
        application.workdaySourcePosting = posting
        posting.trackedApplication = application

        let contact = RecruiterContact()
        contact.fullName = "Jordan Lee"
        contact.email = "jordan@acme.com"
        contact.application = application

        let event = CareerEvent()
        event.title = "Phone screen"
        event.date = .now
        event.application = application
        event.recruiterContact = contact

        profileContext.insert(resume)
        profileContext.insert(posting)
        profileContext.insert(application)
        profileContext.insert(contact)
        profileContext.insert(event)
        try profileContext.save()

        XCTAssertEqual(try profileContext.fetchCount(FetchDescriptor<JobApplication>()), 1)
        XCTAssertEqual(try profileContext.fetchCount(FetchDescriptor<CareerEvent>()), 1)
    }

    func testAppDataStoreBridgeRecordsActiveSchoolID() throws {
        AppDataStoreBridge.syncActiveCatalogSchool(universityName: "Example University")
        let schoolID = CatalogStoreCoordinator.shared.schoolID(for: "Example University")
        XCTAssertFalse(schoolID.isEmpty)
        XCTAssertEqual(UserDefaults.standard.string(forKey: "catalog.activeSchoolID"), schoolID)
    }
}
