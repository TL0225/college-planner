// JobBoardPublicHubPipelineTests.swift
// Feature: Career / Openings / Integration

import Foundation
import Testing
@testable import College

@Suite("JobBoardPublicHubPipelineTests")
@MainActor
struct JobBoardPublicHubPipelineTests {
    @Test("BuiltIn fixture listings import and read")
    func builtInImportPipeline() throws {
        try AppDataStore.shared.clearProfileStoreForUnitTesting()
        let context = AppDataStore.shared.profileContext
        let repo = CareerRepository(context: context)
        let company = JobBoardCompany(
            slug: "builtin",
            displayName: "BuiltIn",
            careersURL: "https://builtin.com/jobs",
            platform: .builtIn
        )
        let html = try TestFixturePaths.jobBoardString(platform: "BuiltIn", named: "builtin-list-page-1.html")
        let base = URL(string: company.careersURL)!
        let listings = JobBoardPublicHubScrapeEngine.parseListings(html: html, baseURL: base, config: .builtIn)
        let count = try repo.applyJobBoardListings(company: company, listings: listings)
        #expect(count == 2)
        let bridge = JobBoardReadBridge.companyPostings(companySlug: "builtin")
        #expect(bridge.count == 2)
        #expect(CareerApplyTier.tier(for: .builtIn) == .manualOnly)
    }
}
