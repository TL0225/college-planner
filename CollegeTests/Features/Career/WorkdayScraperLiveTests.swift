// WorkdayScraperLiveTests.swift
// Feature: Career
// Purpose: Optional live-network Workday scrape validation (offline by default in CI).

import XCTest
@testable import College

@MainActor
final class WorkdayScraperLiveTests: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        try CollegeTestsSupport.skipUnlessLiveNetworkTests()
    }

    func testLiveScrapeInsmedListings() async throws {
        let company = WorkdayCompanyConfigEntry(
            slug: "insmed",
            displayName: "Insmed Incorporated",
            careersURL: "https://insmed.wd5.myworkdayjobs.com/en-US/EXTERNAL"
        )

        let progress = ProgressBox()
        let jobs = try await WorkdayScraper.shared.scrapeCompanyListings(entry: company) { completed, total in
            progress.record(completed: completed, total: total)
        }

        XCTAssertGreaterThanOrEqual(jobs.count, 80, "Expected Insmed board to return most of ~88 postings")
        XCTAssertTrue(jobs.allSatisfy { !$0.title.isEmpty && !$0.externalPath.isEmpty })

        let regularCount = jobs.filter { $0.jobTypeText == "Regular" }.count
        let fullTimeCount = jobs.filter { $0.timeType == "Full time" }.count
        XCTAssertEqual(regularCount, jobs.count, "Insmed external board should tag all jobs as Regular")
        XCTAssertEqual(fullTimeCount, jobs.count, "Insmed external board should tag all jobs as Full time")

        let maxProgress = progress.maxFraction
        XCTAssertGreaterThanOrEqual(maxProgress, 0.99, "Listing scrape should reach ~100% progress")
    }
}

private final class ProgressBox: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [(Int, Int?)] = []

    func record(completed: Int, total: Int?) {
        lock.lock()
        samples.append((completed, total))
        lock.unlock()
    }

    var maxFraction: Double {
        lock.lock()
        defer { lock.unlock() }
        return samples.compactMap { sample -> Double? in
            guard let total = sample.1, total > 0 else { return nil }
            return Double(sample.0) / Double(total)
        }.max() ?? 0
    }
}
