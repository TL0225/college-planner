// NYStateJobsScraperTests.swift
// Feature: Career / Openings / Scrapers

import Foundation
import Testing
@testable import College

@Suite("NYStateJobsScraperTests")
struct NYStateJobsScraperTests {
    @Test("Parses NY State vacancy table fixture")
    func parseList() throws {
        let html = try TestFixturePaths.jobBoardString(platform: "NYStateJobs", named: "ny-statejobs-vacancy-table.html")
        let listings = NYStateJobsHTMLParser.parseListings(html: html)
        #expect(listings.count >= 5)
        #expect(listings.allSatisfy { $0.externalPath.contains("vacancyDetailsView.cfm?id=") })
        #expect(listings.contains(where: { $0.title.contains("Hearing Officer") }))
    }

    @Test("Parses NY State vacancy detail fixture")
    func parseDetail() throws {
        let html = try TestFixturePaths.jobBoardString(platform: "NYStateJobs", named: "ny-statejobs-vacancy-detail.html")
        let detail = NYStateJobsHTMLParser.parseDetail(html: html, fallbackTitle: nil)
        #expect(detail.title?.contains("Hearing Officer") == true)
        #expect(detail.descriptionPlain.contains("Duties"))
        #expect(detail.requirementsPlain?.contains("qualifications") == true)
        #expect(detail.salaryText?.contains("96336") == true)
    }

    @Test("Import pipeline accepts NY State listing shape")
    @MainActor
    func importPipeline() throws {
        try AppDataStore.shared.clearProfileStoreForUnitTesting()
        let repo = CareerRepository(context: AppDataStore.shared.profileContext)
        let company = JobBoardCompany(
            slug: "ny-state-jobs",
            displayName: "NY State Jobs",
            careersURL: "https://statejobs.ny.gov/public/vacancyTable.cfm",
            platform: .nyStateJobs
        )
        let html = try TestFixturePaths.jobBoardString(platform: "NYStateJobs", named: "ny-statejobs-vacancy-table.html")
        let listings = Array(NYStateJobsHTMLParser.parseListings(html: html).prefix(5))
        let count = try repo.applyJobBoardListings(company: company, listings: listings)
        #expect(count == 5)
    }
}
