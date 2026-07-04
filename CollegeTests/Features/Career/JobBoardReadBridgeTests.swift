// JobBoardReadBridgeTests.swift
// Feature: Career
// Purpose: Career module — JobBoardReadBridgeTests.
// Data: CollegePersistence / repositories when applicable.

import SwiftData
import XCTest
@testable import College

@MainActor
final class JobBoardReadBridgeTests: PersistenceTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        for posting in try profileContext.fetch(FetchDescriptor<JobBoardPosting>()) {
            profileContext.delete(posting)
        }
        try profileContext.save()
    }

    func testImportJobBoardListingsWritesStoreOnly() async throws {
        let company = JobBoardCompany(
            slug: "acme",
            displayName: "Acme",
            careersURL: "https://acme.wd1.myworkdayjobs.com/Acme_Careers"
        )
        let listings = [
            ScrapedJobListing(
                externalId: "JR123",
                externalPath: "/job/123",
                title: "Engineer",
                locationText: "Remote",
                postedOn: nil,
                applyURLString: "https://example.com/apply",
                jobTypeText: nil,
                timeType: nil,
                listingHash: "hash-1"
            ),
        ]

        let count = try CollegePersistence.shared.importJobBoardListings(company: company, listings: listings)
        XCTAssertEqual(count, 1)

        let results = JobBoardReadBridge.companyPostings(companySlug: "acme")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.title, "Engineer")
        XCTAssertEqual(results.first?.externalPath, "/job/123")
    }

    func testCompanyPostingsReturnsMatchingSlug() throws {
        let posting = JobBoardPosting(companySlug: "acme", externalId: "JR123", isActive: true)
        posting.externalPath = "/job/123"
        posting.title = "Engineer"
        posting.firstSeenAt = Date()
        profileContext.insert(posting)
        try profileContext.save()

        let results = JobBoardReadBridge.companyPostings(companySlug: "acme")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.externalPath, "/job/123")
        XCTAssertEqual(results.first?.companySlug, "acme")
    }

    func testFetchPostingUsesTargetedLookup() throws {
        let repo = AppDataStore.shared.careerRepository
        for index in 0..<8 {
            let posting = JobBoardPosting(companySlug: "acme", externalId: "JR\(index)", isActive: true)
            posting.externalPath = "/job/\(index)"
            posting.title = "Role \(index)"
            profileContext.insert(posting)
        }
        try profileContext.save()

        let match = try repo.fetchPosting(companySlug: "acme", externalPath: "/job/3")
        XCTAssertEqual(match?.title, "Role 3")
    }

    func testCompanyPostingListDTOsOffMainMatchesMainFetch() async throws {
        for index in 0..<12 {
            let posting = JobBoardPosting(companySlug: "acme", externalId: "JR\(index)", isActive: true)
            posting.externalPath = "/job/\(index)"
            posting.title = "Role \(index)"
            posting.locationText = "Remote"
            profileContext.insert(posting)
        }
        try profileContext.save()

        let dtos = await JobBoardReadBridge.companyPostingListDTOsOffMain(companySlug: "acme")
        XCTAssertEqual(dtos.count, 12)
        XCTAssertEqual(Set(dtos.map(\.title)), Set((0..<12).map { "Role \($0)" }))

        let hydrated = await JobBoardReadBridge.companyPostingsOffMain(companySlug: "acme")
        XCTAssertEqual(hydrated.count, 12)
        XCTAssertEqual(hydrated.first?.companySlug, "acme")
    }
}
