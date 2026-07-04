// JobBoardTrackerTests.swift
// Feature: Career / Openings / Tracker

import Foundation
import SwiftData
import Testing
@testable import College

@Suite("JobBoardTrackerTests")
@MainActor
struct JobBoardTrackerTests {
    @Test("Promote posting links application and posting")
    func promoteLinks() throws {
        try AppDataStore.shared.clearProfileStoreForUnitTesting()
        let context = AppDataStore.shared.profileContext
        let repo = CareerRepository(context: context)
        let posting = WorkdayJobPosting(companySlug: "acme", externalId: "JR-1")
        posting.externalPath = "/job/1"
        posting.title = "Engineer"
        posting.companyDisplayName = "Acme"
        context.insert(posting)
        try context.save()

        let app = try repo.promoteJobBoardPostingToTracker(posting)
        #expect(app.workdaySourcePosting?.id == posting.id)
        #expect(posting.trackedApplication?.id == app.id)
        #expect(app.workdayCompanySlug == "acme")
        #expect(app.workdayExternalId == "JR-1")
    }

    @Test("recommendedMatchIfValid rejects stale hash")
    func recommendedMatchIfValid() throws {
        try AppDataStore.shared.clearProfileStoreForUnitTesting()
        let repo = CareerRepository(context: AppDataStore.shared.profileContext)
        _ = try repo.upsertResumeJobMatch(
            companySlug: "acme",
            externalPath: "/job/1",
            resumeDocumentID: UUID(),
            overallScore: 80,
            keywordScore: 70,
            semanticScore: 70,
            experienceScore: 60,
            missingKeywords: [],
            recommendedForPosting: true,
            resultJSON: nil,
            descriptionHash: "stale",
            resumeHash: "resume"
        )
        let valid = try repo.recommendedMatchIfValid(
            companySlug: "acme",
            externalPath: "/job/1",
            postingDescriptionHash: "fresh",
            resumeParsedTextHash: "resume"
        )
        #expect(valid == nil)
    }
}
