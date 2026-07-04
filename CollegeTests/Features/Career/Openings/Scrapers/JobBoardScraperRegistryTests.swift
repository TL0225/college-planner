// JobBoardScraperRegistryTests.swift
// Feature: Career / Openings / Scrapers

import Foundation
import Testing
@testable import College

@Suite("JobBoardScraperRegistryTests")
struct JobBoardScraperRegistryTests {
    @Test(arguments: JobBoardPlatform.allCases)
    func registryReturnsScraper(platform: JobBoardPlatform) {
        _ = JobBoardScraperRegistry.scraper(for: platform)
    }
}
