// JobBoardDetailTests.swift
// Feature: Career / Openings / Detail

import Foundation
import SwiftData
import Testing
@testable import College

@Suite("JobBoardDetailHashTests")
@MainActor
struct JobBoardDetailHashTests {
    @Test("Description hash uses legacy single-field form")
    func descriptionHash() throws {
        try AppDataStore.shared.clearProfileStoreForUnitTesting()
        let repo = CareerRepository(context: AppDataStore.shared.profileContext)
        let posting = WorkdayJobPosting(companySlug: "acme", externalId: "job-1")
        posting.externalPath = "/job/1"
        AppDataStore.shared.profileContext.insert(posting)
        try AppDataStore.shared.profileContext.save()

        let detail = ScrapedJobDetail(
            title: "Engineer",
            descriptionPlain: "Build APIs with Swift.",
            requirementsPlain: nil,
            locationDisplay: "Remote",
            filterLocations: [],
            postedAt: nil,
            postedOnDisplay: nil,
            workModel: nil,
            jobTypeText: nil,
            timeType: nil,
            salaryText: nil
        )
        try repo.applyJobBoardDetail(posting: posting, detail: detail)
        #expect(
            posting.descriptionHash
                == CareerResumeHashing.hash(jobDescriptionPlain: detail.descriptionPlain)
        )
    }

    @Test("Requirements-only update changes hash and invalidates cache")
    func requirementsHashInvalidates() throws {
        try AppDataStore.shared.clearProfileStoreForUnitTesting()
        let repo = CareerRepository(context: AppDataStore.shared.profileContext)
        let posting = WorkdayJobPosting(companySlug: "acme", externalId: "job-1")
        posting.externalPath = "/job/1"
        AppDataStore.shared.profileContext.insert(posting)
        try AppDataStore.shared.profileContext.save()

        try repo.applyJobBoardDetail(
            posting: posting,
            detail: ScrapedJobDetail(
                title: "Engineer",
                descriptionPlain: "Build APIs.",
                requirementsPlain: nil,
                locationDisplay: nil,
                filterLocations: [],
                postedAt: nil,
                postedOnDisplay: nil,
                workModel: nil,
                jobTypeText: nil,
                timeType: nil,
                salaryText: nil
            )
        )
        let hashA = posting.descriptionHash
        let resumeID = UUID()
        _ = try repo.upsertResumeJobMatch(
            companySlug: "acme",
            externalPath: "/job/1",
            resumeDocumentID: resumeID,
            overallScore: 70,
            keywordScore: 60,
            semanticScore: 65,
            experienceScore: 55,
            missingKeywords: [],
            recommendedForPosting: true,
            resultJSON: nil,
            descriptionHash: hashA,
            resumeHash: "r1"
        )

        try repo.applyJobBoardDetail(
            posting: posting,
            detail: ScrapedJobDetail(
                title: "Engineer",
                descriptionPlain: "Build APIs.",
                requirementsPlain: "5+ years Swift",
                locationDisplay: nil,
                filterLocations: [],
                postedAt: nil,
                postedOnDisplay: nil,
                workModel: nil,
                jobTypeText: nil,
                timeType: nil,
                salaryText: nil
            )
        )
        #expect(posting.descriptionHash != hashA)
        let match = try repo.recommendedMatch(companySlug: "acme", externalPath: "/job/1")
        #expect(match == nil)
    }
}

@Suite("JobBoardDetailScrapeGateTests")
struct JobBoardDetailScrapeGateTests {
    @Test("Fresh posting should fetch detail")
    @MainActor
    func shouldFetchWhenNeverScraped() throws {
        try AppDataStore.shared.clearProfileStoreForUnitTesting()
        let repo = CareerRepository(context: AppDataStore.shared.profileContext)
        let posting = WorkdayJobPosting(companySlug: "acme", externalId: "1")
        posting.externalPath = "/job/1"
        #expect(repo.shouldFetchJobBoardDetail(for: posting, force: false))
    }

    @Test("Recent detail respects TTL unless forced")
    @MainActor
    func ttlGate() throws {
        try AppDataStore.shared.clearProfileStoreForUnitTesting()
        let repo = CareerRepository(context: AppDataStore.shared.profileContext)
        let posting = WorkdayJobPosting(companySlug: "acme", externalId: "1")
        posting.externalPath = "/job/1"
        posting.detailScrapedAt = .now
        #expect(repo.shouldFetchJobBoardDetail(for: posting, force: false) == false)
        #expect(repo.shouldFetchJobBoardDetail(for: posting, force: true))
    }
}
