// JobBoardSyncTests.swift
// Feature: Career / Openings / Sync

import Foundation
import Testing
@testable import College

@Suite("JobBoardSyncTests")
struct JobBoardSyncTests {
    @Test("Scrape cooldown is 30 seconds")
    func scrapeCooldown() {
        #expect(JobBoardThresholds.minScrapeCooldown == 30)
    }

    @Test("Detail cache TTL is 48 hours")
    func detailTTL() {
        #expect(JobBoardThresholds.detailCacheTTL == 48 * 3600)
    }

    @Test("Default refresh interval is 12 hours")
    func defaultRefresh() {
        #expect(JobBoardThresholds.defaultRefreshInterval == 12 * 3600)
    }
}
