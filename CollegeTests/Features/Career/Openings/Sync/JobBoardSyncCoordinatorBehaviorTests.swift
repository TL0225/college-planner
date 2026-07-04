// JobBoardSyncCoordinatorBehaviorTests.swift
// Feature: Career / Openings / Sync

import Foundation
import Testing
@testable import College

@Suite("JobBoardSyncCoordinatorBehaviorTests")
@MainActor
struct JobBoardSyncCoordinatorBehaviorTests {
    private let companiesKey = "workday.companies.v1"

    @Test("scrapeCompany skips when last scrape is within refresh interval")
    func scrapeRefreshIntervalSkip() async throws {
        let defaults = UserDefaults.standard
        let originalCompanies = defaults.data(forKey: companiesKey)
        defer {
            defaults.set(originalCompanies, forKey: companiesKey)
            JobBoardCompaniesStore.shared.loadFromUserDefaults()
        }

        try AppDataStore.shared.clearProfileStoreForUnitTesting()
        defaults.removeObject(forKey: companiesKey)
        JobBoardCompaniesStore.shared.loadFromUserDefaults()

        JobBoardCompaniesStore.shared.addCompany(
            displayName: "Cooldown Co",
            careersURL: "https://example.com/jobs",
            platform: .yCombinator
        )
        let company = try #require(JobBoardCompaniesStore.shared.companies.first)

        let repo = CareerRepository(context: AppDataStore.shared.profileContext)
        _ = try repo.applyJobBoardListings(company: company, listings: [
            ScrapedJobListing(
                externalId: "cool-1",
                externalPath: "/companies/acme/jobs/cool-1",
                title: "Engineer",
                locationText: "Remote",
                postedOn: nil,
                applyURLString: "https://example.com/jobs/cool-1",
                jobTypeText: nil,
                timeType: nil,
                listingHash: "hash-cool-1"
            ),
        ])
        JobBoardRefreshScheduler.recordLastScraped(slug: company.normalizedSlug, at: Date())

        let coordinator = JobBoardSyncCoordinator.shared
        coordinator.rebuildIdleUIState()
        await coordinator.scrapeCompany(company, force: false)

        #expect(coordinator.isScraping(slug: company.normalizedSlug) == false)
    }

    @Test("shouldAutoRefresh is false when postings were scraped recently")
    func shouldAutoRefreshRespectsInterval() {
        let slug = "fresh-company"
        JobBoardRefreshScheduler.recordLastScraped(slug: slug, at: Date())
        #expect(JobBoardRefreshScheduler.shared.shouldAutoRefresh(slug: slug) == false)
    }

    @Test("shouldAutoRefresh is false when cached postings exist without UserDefaults stamp")
    func shouldAutoRefreshBackfillsPersistedPostings() throws {
        let defaults = UserDefaults.standard
        let originalCompanies = defaults.data(forKey: companiesKey)
        defer {
            defaults.set(originalCompanies, forKey: companiesKey)
            JobBoardCompaniesStore.shared.loadFromUserDefaults()
            defaults.removeObject(forKey: JobBoardRefreshScheduler.lastScrapedKey(slug: "persisted-co"))
        }

        try AppDataStore.shared.clearProfileStoreForUnitTesting()
        defaults.removeObject(forKey: companiesKey)
        JobBoardCompaniesStore.shared.loadFromUserDefaults()

        JobBoardCompaniesStore.shared.addCompany(
            displayName: "Persisted Co",
            careersURL: "https://example.com/persisted",
            slug: "persisted-co",
            platform: .yCombinator
        )
        let company = try #require(JobBoardCompaniesStore.shared.companies.first)
        defaults.removeObject(forKey: JobBoardRefreshScheduler.lastScrapedKey(slug: company.normalizedSlug))

        let repo = CareerRepository(context: AppDataStore.shared.profileContext)
        _ = try repo.applyJobBoardListings(company: company, listings: [
            ScrapedJobListing(
                externalId: "persisted-1",
                externalPath: "/companies/persisted/jobs/persisted-1",
                title: "Engineer",
                locationText: "Remote",
                postedOn: nil,
                applyURLString: "https://example.com/persisted-1",
                jobTypeText: nil,
                timeType: nil,
                listingHash: "hash-persisted-1"
            ),
        ])

        #expect(JobBoardRefreshScheduler.shared.shouldAutoRefresh(slug: company.normalizedSlug) == false)
        #expect(JobBoardRefreshScheduler.lastScraped(slug: company.normalizedSlug) != nil)
    }

    @Test("failed scrape backoff is active immediately after attempt")
    func failureBackoffState() {
        let slug = "backoff-test"
        JobBoardRefreshScheduler.recordLastAttempted(slug: slug, at: Date())
        #expect(JobBoardRefreshScheduler.isInFailureBackoff(slug: slug))
    }

    @Test("persisted failure status survives rebuildIdleUIState")
    func persistedFailureStatusSurvivesRebuild() throws {
        let defaults = UserDefaults.standard
        let originalCompanies = defaults.data(forKey: companiesKey)
        let slug = "failed-co"
        defer {
            defaults.set(originalCompanies, forKey: companiesKey)
            JobBoardCompaniesStore.shared.loadFromUserDefaults()
            defaults.removeObject(forKey: JobBoardRefreshScheduler.lastAttemptedKey(slug: slug))
            JobBoardRefreshScheduler.clearLastSyncError(slug: slug)
        }

        try AppDataStore.shared.clearProfileStoreForUnitTesting()
        defaults.removeObject(forKey: companiesKey)
        JobBoardCompaniesStore.shared.loadFromUserDefaults()
        JobBoardCompaniesStore.shared.addCompany(
            displayName: "Failed Co",
            careersURL: "https://example.com/jobs",
            slug: slug,
            platform: .workday
        )

        JobBoardRefreshScheduler.recordLastAttempted(slug: slug, at: Date())
        JobBoardRefreshScheduler.recordLastSyncError(
            slug: slug,
            message: "Workday careers site is temporarily down for maintenance."
        )

        let coordinator = JobBoardSyncCoordinator.shared
        coordinator.rebuildIdleUIState()

        let state = try #require(coordinator.uiState.companies.first { $0.slug == slug })
        if case .error(let err, _) = state.status {
            #expect(err.displayMessage.contains("maintenance"))
        } else {
            Issue.record("Expected persisted failure status, got \(state.status)")
        }
    }
}
