// JobBoardBoardFingerprintTests.swift
// Feature: Career / Openings / Sync

import Foundation
import Testing
@testable import College

@Suite("JobBoardBoardFingerprintTests")
struct JobBoardBoardFingerprintTests {
    @Test("digest is stable for identical listings")
    func digestStability() {
        let listings = [
            ScrapedJobListing(
                externalId: "JR1",
                externalPath: "/job/a",
                title: "Engineer",
                locationText: "Remote",
                postedOn: nil,
                applyURLString: nil,
                jobTypeText: nil,
                timeType: nil,
                listingHash: "hash-a"
            ),
        ]
        let a = JobBoardBoardFingerprint.digest(listings: listings)
        let b = JobBoardBoardFingerprint.digest(listings: listings)
        #expect(a == b)
    }

    @Test("full list scrape is due when never recorded")
    func fullScrapeDueWhenMissing() {
        let slug = "fingerprint-test-co"
        defer { UserDefaults.standard.removeObject(forKey: "workday.lastFullListScrapeAt.\(slug)") }
        #expect(JobBoardBoardFingerprintStore.isDueForFullListScrape(slug: slug))
    }

    @Test("quick check rejects matching fingerprint when local count drifts")
    @MainActor
    func quickCheckRejectsCountDrift() throws {
        try AppDataStore.shared.clearProfileStoreForUnitTesting()
        let slug = "drift-co"
        let fingerprint = JobBoardBoardFingerprint(boardTotal: 2, pageDigest: "abc")
        let probe = JobBoardBoardProbeResult(
            fingerprint: fingerprint,
            firstPageListings: []
        )
        let company = JobBoardCompany(slug: slug, displayName: "Drift", careersURL: "https://example.com/jobs")
        let repo = CareerRepository(context: AppDataStore.shared.profileContext)
        _ = try repo.applyJobBoardListings(company: company, listings: [
            ScrapedJobListing(
                externalId: "1", externalPath: "/job/1", title: "A", locationText: "Remote",
                postedOn: nil, applyURLString: nil, jobTypeText: nil, timeType: nil, listingHash: "a"
            ),
        ])
        #expect(
            JobBoardSyncCoordinator.canQuickCheckSkipFullScrape(
                probe: probe,
                stored: fingerprint,
                slug: slug
            ) == false
        )
    }
}
