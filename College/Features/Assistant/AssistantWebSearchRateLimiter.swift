// AssistantWebSearchRateLimiter.swift
// Feature: Assistant
// Purpose: Assistant module — AssistantWebSearchRateLimiter.
// Data: CollegePersistence / repositories when applicable.

import Foundation

/// Per-session limits for SearXNG + page fetch tools (no PII in telemetry).
actor AssistantWebSearchRateLimiter {

    static let shared = AssistantWebSearchRateLimiter()

    private var searchCount = 0
    private var fetchCount = 0
    private var windowStart = Date()
    private var lastSearchFailureAt: Date?
    private let windowSeconds: TimeInterval = 60
    private let maxSearchesPerWindow = 8
    private let maxFetchesPerWindow = 6
    private let failureCooldown: TimeInterval = 45

    func allowSearch() -> Bool {
        rollWindowIfNeeded()
        if let t = lastSearchFailureAt, Date().timeIntervalSince(t) < failureCooldown {
            return false
        }
        guard searchCount < maxSearchesPerWindow else { return false }
        searchCount += 1
        return true
    }

    func allowFetch() -> Bool {
        rollWindowIfNeeded()
        guard fetchCount < maxFetchesPerWindow else { return false }
        fetchCount += 1
        return true
    }

    func noteSearchFailure() {
        lastSearchFailureAt = Date()
    }

    private func rollWindowIfNeeded() {
        let now = Date()
        if now.timeIntervalSince(windowStart) >= windowSeconds {
            windowStart = now
            searchCount = 0
            fetchCount = 0
        }
    }

    #if DEBUG
    func resetForTesting() {
        searchCount = 0
        fetchCount = 0
        windowStart = Date()
        lastSearchFailureAt = nil
    }
    #endif
}
