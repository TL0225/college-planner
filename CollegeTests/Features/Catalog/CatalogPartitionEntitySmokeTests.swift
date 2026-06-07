// CatalogPartitionEntitySmokeTests.swift
// Feature: Catalog
// Purpose: Catalog module — CatalogPartitionEntitySmokeTests.
// Data: CollegePersistence / repositories when applicable.

import SwiftData
import XCTest
@testable import College

final class CatalogPartitionEntitySmokeTests: PersistenceTestCase {
    override var includesCatalog: Bool { true }

    func testMajorAndScrapeStateRoundTrip() throws {
        let ctx = try XCTUnwrap(catalogContext)
        let uni = University(name: "Smoke U", isActive: true)
        ctx.insert(uni)

        let major = Major(name: "Computer Science", degreeLevel: "Undergraduate", isMinor: false)
        major.university = uni

        let scrape = CatalogScrapeState(catoid: "12345", lastScrapedAt: .now)
        scrape.university = uni

        ctx.insert(major)
        ctx.insert(scrape)
        try ctx.save()

        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<Major>()), 1)
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<CatalogScrapeState>()), 1)
    }

    func testRequirementFulfillmentRoundTrip() throws {
        let ctx = try XCTUnwrap(catalogContext)
        let fulfillment = RequirementFulfillment(
            university: "Smoke U",
            programURL: "https://example.edu/cs",
            requirementCategory: "Core",
            courseCode: "CS 101"
        )
        ctx.insert(fulfillment)
        try ctx.save()
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<RequirementFulfillment>()), 1)
    }

    func testFetchMajorsBounded() throws {
        let ctx = try XCTUnwrap(catalogContext)
        let uni = University(name: "Major U", isActive: true)
        ctx.insert(uni)
        let major = Major(name: "Biology", degreeLevel: "Undergraduate")
        major.university = uni
        ctx.insert(major)
        try ctx.save()

        let repo = CatalogRepository(context: ctx)
        let majors = try repo.fetchMajors(universityID: uni.id, limit: 10)
        XCTAssertEqual(majors.count, 1)
        XCTAssertEqual(majors.first?.name, "Biology")
    }

    func testUpsertCourseScrapeStateUsesMergeCoalescer() throws {
        let ctx = try XCTUnwrap(catalogContext)
        let uniID = UUID()
        let repo = CatalogRepository(context: ctx)
        _ = try repo.ensureUniversity(id: uniID, name: "Mirror U", isActive: true)
        try repo.upsertCourseScrapeState(
            universityID: uniID,
            catoid: "999",
            catalogTitle: "Undergraduate",
            courseCount: 42
        )
        ModelMergeCoalescer.flushNow()

        let states = try ctx.fetch(FetchDescriptor<CatalogScrapeState>())
        XCTAssertEqual(states.count, 1)
        XCTAssertEqual(states.first?.catoid, "999")
        XCTAssertEqual(states.first?.courseCount, 42)
        XCTAssertEqual(states.first?.catalogTitle, "Undergraduate")
    }
}
