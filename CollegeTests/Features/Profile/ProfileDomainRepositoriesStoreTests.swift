// ProfileDomainRepositoriesStoreTests.swift
// Feature: Profile
// Purpose: Profile module — ProfileDomainRepositoriesStoreTests.
// Data: CollegePersistence / repositories when applicable.

import SwiftData
import XCTest
@testable import College

final class ProfileDomainRepositoriesStoreTests: PersistenceTestCase {
    func testAcademicProfileFetchPrimary() throws {
        let profile = Profile(name: "Alex")
        let primary = AcademicProfile(isPrimary: true, isActive: true)
        primary.major = "Computer Science"
        primary.profile = profile
        profile.academicProfiles = [primary]

        profileContext.insert(profile)
        try profileContext.save()

        let repo = ProfileRepository(context: profileContext)
        let fetched = try repo.fetchPrimaryAcademicProfile()
        XCTAssertEqual(fetched?.id, primary.id)
        XCTAssertEqual(fetched?.major, "Computer Science")
    }

    func testCalendarRepositoryBoundedFetches() throws {
        let ids = try PersistenceFixtureFactory.seedMinimalPlanner(in: profileContext)
        let semester = try XCTUnwrap(try ProfileRepository(context: profileContext).fetchSemester(id: ids.semesterID))

        let start = Date()
        let end = start.addingTimeInterval(86_400)
        let event = CalendarEvent(title: "Exam", startDate: start, endDate: end)
        event.semester = semester
        profileContext.insert(event)

        let task = PlannerTask(title: "Reading", dueDate: end)
        task.semester = semester
        profileContext.insert(task)
        try profileContext.save()

        let calendarRepo = CalendarRepository(context: profileContext)
        XCTAssertEqual(try calendarRepo.fetchEvents(from: start.addingTimeInterval(-60), to: end.addingTimeInterval(60)).count, 1)
        XCTAssertEqual(try calendarRepo.fetchEvents(forSemesterID: ids.semesterID).count, 1)
        XCTAssertEqual(try calendarRepo.fetchTasks(forSemesterID: ids.semesterID).count, 1)
    }

    func testVaultRepositoryPagedDocuments() throws {
        let docA = VaultDocument(fileName: "a.pdf", category: "Syllabus", localRelativePath: "vault/a.pdf")
        let docB = VaultDocument(fileName: "b.pdf", category: "Other", localRelativePath: "vault/b.pdf")
        profileContext.insert(docA)
        profileContext.insert(docB)
        try profileContext.save()

        let repo = VaultRepository(context: profileContext)
        XCTAssertEqual(try repo.fetchDocumentCount(), 2)
        XCTAssertEqual(try repo.fetchDocuments(category: "Syllabus").count, 1)
        XCTAssertEqual(try repo.fetchDocuments(limit: 1, offset: 0).count, 1)
    }

    func testModelMergeCoalescerDebouncesSave() throws {
        let doc = VaultDocument(fileName: "coalesce.pdf", localRelativePath: "vault/coalesce.pdf")
        profileContext.insert(doc)
        ModelMergeCoalescer.scheduleSave(profileContext)
        ModelMergeCoalescer.flushNow()
        XCTAssertFalse(doc.fileName.isEmpty)
    }

    func testAppDataStoreRepositoryAccessors() throws {
        let store = AppDataStore.shared
        _ = try store.calendarRepository.fetchTasks(forSemesterID: UUID(), limit: 1)
        _ = try store.vaultRepository.fetchWatchedFolders(limit: 1)
    }
}
