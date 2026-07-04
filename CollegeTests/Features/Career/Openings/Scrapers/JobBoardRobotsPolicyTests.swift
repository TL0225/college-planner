// JobBoardRobotsPolicyTests.swift
// Feature: Career / Openings / Scrapers

import Foundation
import Testing
@testable import College

@Suite("JobBoardRobotsPolicyTests")
struct JobBoardRobotsPolicyTests {
    @Test("BuiltIn hub URLs allowed")
    func builtInHubAllowed() {
        let url = URL(string: "https://builtin.com/jobs")!
        #expect(JobBoardRobotsPolicy.isAllowedBuiltInHubURL(url))
        let paged = URL(string: "https://builtin.com/jobs?page=2")!
        #expect(JobBoardRobotsPolicy.isAllowedBuiltInHubURL(paged))
    }

    @Test("BuiltIn search and regional URLs blocked")
    func builtInDisallowed() {
        let search = URL(string: "https://builtin.com/jobs?search=swift")!
        #expect(!JobBoardRobotsPolicy.isAllowedBuiltInHubURL(search))
        let regional = URL(string: "https://builtin.com/jobs/seattle")!
        #expect(!JobBoardRobotsPolicy.isAllowedBuiltInHubURL(regional))
        let apply = URL(string: "https://builtin.com/apply/123")!
        #expect(!JobBoardRobotsPolicy.isAllowedBuiltInHubURL(apply))
    }

    @Test("Parses robots disallow rules")
    func parseRobots() throws {
        let body = try TestFixturePaths.jobBoardSharedString(named: "robots-deny-search.builtin.txt")
        let rules = JobBoardRobotsPolicy.parseRules(from: body)
        #expect(!rules.isEmpty)
        #expect(body.lowercased().contains("disallow"))
    }

    @Test("RemoteOK crawl delay parsed")
    func remoteOKCrawlDelay() {
        let body = """
        User-agent: *
        Allow: /
        Crawl-delay: 1
        """
        #expect(JobBoardRobotsPolicy.parseCrawlDelay(from: body) == 1)
    }

    @Test("Seeded robots blocks disallowed path")
    func seededRobots() async {
        await JobBoardRobotsPolicy.resetCacheForTesting()
        await JobBoardRobotsPolicy.seedRobotsForTesting(
            host: "builtin.com",
            body: try! TestFixturePaths.jobBoardString(platform: "BuiltIn", named: "robots.txt")
        )
        let search = URL(string: "https://builtin.com/jobs?search=engineer")!
        let reason = await JobBoardRobotsPolicy.disallowedReason(for: search)
        #expect(reason != nil)
    }
}
