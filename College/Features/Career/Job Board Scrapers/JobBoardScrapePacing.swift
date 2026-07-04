// JobBoardScrapePacing.swift
// Feature: Career / Job Board Scrapers
// Purpose: Per-platform minimum delay between HTTP requests.

import Foundation

actor JobBoardScrapePacing {
    static let shared = JobBoardScrapePacing()

    private var lastRequestAt: [JobBoardPlatform: Date] = [:]

    func waitBeforeRequest(platform: JobBoardPlatform, host: String) async {
        let robotsDelay = await JobBoardRobotsPolicy.crawlDelay(forHost: host) ?? 0
        let platformDelay = Self.defaultDelay(for: platform)
        let delay = max(robotsDelay, platformDelay)
        if let last = lastRequestAt[platform] {
            let elapsed = Date().timeIntervalSince(last)
            if elapsed < delay {
                let wait = delay - elapsed
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            }
        }
        lastRequestAt[platform] = Date()
    }

    func resetForTesting() {
        lastRequestAt.removeAll()
    }

    static func defaultDelay(for platform: JobBoardPlatform) -> TimeInterval {
        switch platform {
        case .builtIn: return 2.0
        case .remoteOK: return 1.0
        case .jobicy, .yCombinator: return 1.5
        case .nycCityJobs, .nyStateJobs: return 1.0
        default: return 0.5
        }
    }
}
