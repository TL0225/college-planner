// JobBoardImportPipelineTests.swift
// Feature: Career / Openings / Import

import Foundation
import SwiftData
import Testing
@testable import College

@Suite("JobBoardImportPipelineTests")
@MainActor
struct JobBoardImportPipelineTests {
    private func makeRepo() throws -> (CareerRepository, ModelContext) {
        try AppDataStore.shared.clearProfileStoreForUnitTesting()
        let context = AppDataStore.shared.profileContext
        return (CareerRepository(context: context), context)
    }

    @Test("New listing sets firstSeenAt")
    func firstSeenAtOnImport() throws {
        let (repo, _) = try makeRepo()
        let company = JobBoardCompany(slug: "acme", displayName: "Acme", careersURL: "https://acme.example/jobs")
        let listings = [
            ScrapedJobListing(
                externalId: "1",
                externalPath: "/job/1",
                title: "Engineer",
                locationText: "Remote",
                postedOn: nil,
                applyURLString: nil,
                jobTypeText: nil,
                timeType: nil,
                listingHash: "hash-a"
            ),
        ]
        _ = try repo.applyJobBoardListings(company: company, listings: listings)
        let posting = try repo.fetchPosting(companySlug: "acme", externalPath: "/job/1")
        #expect(posting?.firstSeenAt != nil)
        #expect(posting?.title == "Engineer")
    }

    @Test("Partial page import does not deactivate missing postings")
    func partialPagePreservesActiveUntilFinalize() throws {
        let (repo, _) = try makeRepo()
        let company = JobBoardCompany(slug: "acme", displayName: "Acme", careersURL: "https://acme.example/jobs")
        _ = try repo.applyJobBoardListings(company: company, listings: [
            ScrapedJobListing(
                externalId: "1", externalPath: "/job/1", title: "A", locationText: "Remote",
                postedOn: nil, applyURLString: nil, jobTypeText: nil, timeType: nil, listingHash: "a"
            ),
            ScrapedJobListing(
                externalId: "2", externalPath: "/job/2", title: "B", locationText: "Remote",
                postedOn: nil, applyURLString: nil, jobTypeText: nil, timeType: nil, listingHash: "b"
            ),
        ])

        let session = repo.beginJobBoardListImport(company: company)
        _ = try session.mergePage([
            ScrapedJobListing(
                externalId: "1", externalPath: "/job/1", title: "A", locationText: "Remote",
                postedOn: nil, applyURLString: nil, jobTypeText: nil, timeType: nil, listingHash: "a"
            ),
        ])
        let midSync = try repo.fetchPosting(companySlug: "acme", externalPath: "/job/2")
        #expect(midSync?.isActive == true)

        _ = try session.finalizeRemovals()
        let afterFinalize = try repo.fetchPosting(companySlug: "acme", externalPath: "/job/2")
        #expect(afterFinalize?.isActive == false)
    }

    @Test("Unchanged listing hash skips field rewrite")
    func hashSkipPreservesTitle() throws {
        let (repo, context) = try makeRepo()
        let company = JobBoardCompany(slug: "acme", displayName: "Acme", careersURL: "https://acme.example/jobs")
        let listing = ScrapedJobListing(
            externalId: "1",
            externalPath: "/job/1",
            title: "Engineer",
            locationText: "Remote",
            postedOn: nil,
            applyURLString: nil,
            jobTypeText: nil,
            timeType: nil,
            listingHash: "hash-a"
        )
        _ = try repo.applyJobBoardListings(company: company, listings: [listing])
        let firstSeen = try repo.fetchPosting(companySlug: "acme", externalPath: "/job/1")?.firstSeenAt

        let updated = ScrapedJobListing(
            externalId: "1",
            externalPath: "/job/1",
            title: "Senior Engineer",
            locationText: "Remote",
            postedOn: nil,
            applyURLString: nil,
            jobTypeText: nil,
            timeType: nil,
            listingHash: "hash-a"
        )
        _ = try repo.applyJobBoardListings(company: company, listings: [updated])
        try context.save()

        let posting = try repo.fetchPosting(companySlug: "acme", externalPath: "/job/1")
        #expect(posting?.title == "Engineer")
        #expect(posting?.firstSeenAt == firstSeen)
    }

    @Test("Listing hash change clears detailScrapedAt")
    func hashChangeClearsDetail() throws {
        let (repo, _) = try makeRepo()
        let company = JobBoardCompany(slug: "acme", displayName: "Acme", careersURL: "https://acme.example/jobs")
        _ = try repo.applyJobBoardListings(company: company, listings: [
            ScrapedJobListing(
                externalId: "1", externalPath: "/job/1", title: "Engineer", locationText: "Remote",
                postedOn: nil, applyURLString: nil, jobTypeText: nil, timeType: nil, listingHash: "hash-a"
            ),
        ])
        let posting = try #require(try repo.fetchPosting(companySlug: "acme", externalPath: "/job/1"))
        posting.detailScrapedAt = .now
        posting.jobDescriptionText = "Old JD"
        try AppDataStore.shared.profileContext.save()

        _ = try repo.applyJobBoardListings(company: company, listings: [
            ScrapedJobListing(
                externalId: "1", externalPath: "/job/1", title: "Engineer II", locationText: "Remote",
                postedOn: nil, applyURLString: nil, jobTypeText: nil, timeType: nil, listingHash: "hash-b"
            ),
        ])
        let refreshed = try repo.fetchPosting(companySlug: "acme", externalPath: "/job/1")
        #expect(refreshed?.detailScrapedAt == nil)
        #expect(refreshed?.title == "Engineer II")
    }

    @Test("Missing listing paths are deactivated")
    func deactivateMissing() throws {
        let (repo, _) = try makeRepo()
        let company = JobBoardCompany(slug: "acme", displayName: "Acme", careersURL: "https://acme.example/jobs")
        _ = try repo.applyJobBoardListings(company: company, listings: [
            ScrapedJobListing(
                externalId: "1", externalPath: "/job/1", title: "A", locationText: "Remote",
                postedOn: nil, applyURLString: nil, jobTypeText: nil, timeType: nil, listingHash: "a"
            ),
            ScrapedJobListing(
                externalId: "2", externalPath: "/job/2", title: "B", locationText: "Remote",
                postedOn: nil, applyURLString: nil, jobTypeText: nil, timeType: nil, listingHash: "b"
            ),
        ])
        _ = try repo.applyJobBoardListings(company: company, listings: [
            ScrapedJobListing(
                externalId: "1", externalPath: "/job/1", title: "A", locationText: "Remote",
                postedOn: nil, applyURLString: nil, jobTypeText: nil, timeType: nil, listingHash: "a"
            ),
        ])
        let inactive = try repo.fetchPosting(companySlug: "acme", externalPath: "/job/2")
        #expect(inactive?.isActive == false)
    }

    @Test("Workday path variants map to the same stored listing")
    func workdayPathNormalizationOnReimport() throws {
        let (repo, _) = try makeRepo()
        let company = JobBoardCompany(
            slug: "nvidia",
            displayName: "NVIDIA",
            careersURL: "https://nvidia.wd5.myworkdayjobs.com/en-US/NVIDIAExternalCareerSite",
            platform: .workday
        )
        _ = try repo.applyJobBoardListings(company: company, listings: [
            ScrapedJobListing(
                externalId: "JR1",
                externalPath: "/en-US/NVIDIAExternalCareerSite/job/US-CA-Santa-Clara/Role_JR1",
                title: "Engineer",
                locationText: "Remote",
                postedOn: nil,
                applyURLString: nil,
                jobTypeText: nil,
                timeType: nil,
                listingHash: "a"
            ),
        ])
        _ = try repo.applyJobBoardListings(company: company, listings: [
            ScrapedJobListing(
                externalId: "JR1",
                externalPath: "/job/US-CA-Santa-Clara/Role_JR1",
                title: "Engineer",
                locationText: "Remote",
                postedOn: nil,
                applyURLString: nil,
                jobTypeText: nil,
                timeType: nil,
                listingHash: "a"
            ),
        ])
        let active = try repo.fetchCompanyPostings(companySlug: "nvidia").filter(\.isActive)
        #expect(active.count == 1)
    }

    @Test("Empty import does not deactivate existing postings")
    func emptyImportPreservesActivePostings() throws {
        let (repo, _) = try makeRepo()
        let company = JobBoardCompany(slug: "acme", displayName: "Acme", careersURL: "https://acme.example/jobs")
        _ = try repo.applyJobBoardListings(company: company, listings: [
            ScrapedJobListing(
                externalId: "1", externalPath: "/job/1", title: "A", locationText: "Remote",
                postedOn: nil, applyURLString: nil, jobTypeText: nil, timeType: nil, listingHash: "a"
            ),
        ])
        _ = try repo.applyJobBoardListings(company: company, listings: [])
        let posting = try repo.fetchPosting(companySlug: "acme", externalPath: "/job/1")
        #expect(posting?.isActive == true)
    }
}
