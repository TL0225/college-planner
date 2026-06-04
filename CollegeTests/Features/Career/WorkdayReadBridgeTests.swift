// WorkdayReadBridgeTests.swift
// Feature: Career
// Purpose: Career module — WorkdayReadBridgeTests.
// Data: CollegePersistence / repositories when applicable.

import SwiftData
import XCTest
@testable import College

@MainActor
final class WorkdayReadBridgeTests: PersistenceTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        for posting in try profileContext.fetch(FetchDescriptor<WorkdayJobPosting>()) {
            profileContext.delete(posting)
        }
        try profileContext.save()
    }

    func testImportJobBoardListingsWritesStoreOnly() async throws {
        let company = WorkdayCompanyConfigEntry(
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

        let count = await CollegePersistence.shared.importJobBoardListings(company: company, listings: listings)
        XCTAssertEqual(count, 1)

        let results = WorkdayReadBridge.companyPostings(companySlug: "acme")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.title, "Engineer")
        XCTAssertEqual(results.first?.externalPath, "/job/123")
    }

    func testCompanyPostingsReturnsMatchingSlug() throws {
        let posting = WorkdayJobPosting(companySlug: "acme", externalId: "JR123", isActive: true)
        posting.externalPath = "/job/123"
        posting.title = "Engineer"
        posting.firstSeenAt = Date()
        profileContext.insert(posting)
        try profileContext.save()

        let results = WorkdayReadBridge.companyPostings(companySlug: "acme")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.externalPath, "/job/123")
        XCTAssertEqual(results.first?.companySlug, "acme")
    }
}
