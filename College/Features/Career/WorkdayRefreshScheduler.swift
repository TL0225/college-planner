// WorkdayRefreshScheduler.swift
// Feature: Career
// Purpose: Career module — WorkdayRefreshScheduler.
// Data: CollegePersistence / repositories when applicable.

import AppKit
import Foundation

/// Schedules periodic job-board list scrapes on macOS (best-effort; macOS may defer fires).
@MainActor
final class WorkdayRefreshScheduler {
    static let shared = WorkdayRefreshScheduler()

    static let refreshIntervalStorageKey = "workday.refreshInterval"

    private var scheduler: NSBackgroundActivityScheduler?
    private var becameActiveObserver: NSObjectProtocol?
    private var didStart = false
    private var lastOverdueCheckAt: Date?

    /// Minimum gap between automatic overdue checks (avoids duplicate scrapes on rapid app focus).
    private static let overdueCheckCooldown: TimeInterval = 5 * 60

    private init() {}

    func start() {
        guard !didStart else { return }
        didStart = true
        registerBackgroundScheduler()
        becameActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.refreshOverdueCompaniesIfNeeded()
            }
        }
    }

    func stop() {
        scheduler?.invalidate()
        scheduler = nil
        if let becameActiveObserver {
            NotificationCenter.default.removeObserver(becameActiveObserver)
            self.becameActiveObserver = nil
        }
        didStart = false
    }

    func reschedule() {
        scheduler?.invalidate()
        scheduler = nil
        registerBackgroundScheduler()
    }

    var selectedIntervalSeconds: TimeInterval {
        guard UserDefaults.standard.object(forKey: Self.refreshIntervalStorageKey) != nil else {
            return WorkdayJobBoardThresholds.defaultRefreshInterval
        }
        let stored = UserDefaults.standard.integer(forKey: Self.refreshIntervalStorageKey)
        if stored == WorkdayRefreshIntervalOption.manual.rawValue { return 0 }
        return TimeInterval(stored)
    }

    var isManualOnly: Bool {
        guard UserDefaults.standard.object(forKey: Self.refreshIntervalStorageKey) != nil else { return false }
        return UserDefaults.standard.integer(forKey: Self.refreshIntervalStorageKey) == WorkdayRefreshIntervalOption.manual.rawValue
    }

    /// Scrapes only companies whose last successful scrape is older than the configured interval.
    func refreshOverdueCompaniesIfNeeded() async {
        guard !isManualOnly else { return }
        let interval = selectedIntervalSeconds
        guard interval > 0 else { return }

        let now = Date()
        if let lastCheck = lastOverdueCheckAt,
           now.timeIntervalSince(lastCheck) < Self.overdueCheckCooldown {
            return
        }
        lastOverdueCheckAt = now

        let store = WorkdayCompaniesStore.shared
        for company in store.enabledCompanies {
            let slug = company.normalizedSlug

            if WorkdayJobBoardSyncCoordinator.shared.isScraping(slug: slug) {
                continue
            }

            // Skip if the last successful scrape is still within the refresh interval.
            if let last = UserDefaults.standard.object(forKey: Self.lastScrapedKey(slug: slug)) as? Date,
               now.timeIntervalSince(last) < interval {
                continue
            }

            // Skip if a recent failure is still within the back-off window.
            if Self.isInFailureBackoff(slug: slug) {
                continue
            }

            await WorkdayJobBoardSyncCoordinator.shared.scrapeCompany(company)
        }
    }

    /// Minimum back-off after a failed scrape before the scheduler will try again.
    /// Prevents hammering a server that is rate-limiting or returning errors.
    static let failedScrapeBackoff: TimeInterval = 30 * 60

    static func lastScrapedKey(slug: String) -> String {
        "workday.lastScrapedAt.\(slug)"
    }

    static func lastAttemptedKey(slug: String) -> String {
        "workday.lastAttemptedAt.\(slug)"
    }

    static func recordLastScraped(slug: String, at date: Date = Date()) {
        UserDefaults.standard.set(date, forKey: lastScrapedKey(slug: slug))
        // A successful scrape also counts as an attempt; clear any separate attempt marker.
        UserDefaults.standard.removeObject(forKey: lastAttemptedKey(slug: slug))
    }

    /// Call when a scrape fails so the scheduler backs off instead of retrying immediately.
    static func recordLastAttempted(slug: String, at date: Date = Date()) {
        UserDefaults.standard.set(date, forKey: lastAttemptedKey(slug: slug))
    }

    static func lastScraped(slug: String) -> Date? {
        UserDefaults.standard.object(forKey: lastScrapedKey(slug: slug)) as? Date
    }

    static func isInFailureBackoff(slug: String) -> Bool {
        guard let lastAttempt = UserDefaults.standard.object(forKey: lastAttemptedKey(slug: slug)) as? Date else {
            return false
        }
        return Date().timeIntervalSince(lastAttempt) < failedScrapeBackoff
    }

    private func registerBackgroundScheduler() {
        let intervalSeconds = selectedIntervalSeconds
        guard intervalSeconds > 0 else { return }

        let activity = NSBackgroundActivityScheduler(identifier: "com.college.workday.refresh")
        activity.repeats = true
        activity.interval = intervalSeconds
        activity.tolerance = intervalSeconds * 0.2
        activity.qualityOfService = .utility
        activity.schedule { [weak self] completion in
            Task { @MainActor in
                await self?.refreshOverdueCompaniesIfNeeded()
                completion(.finished)
            }
        }
        scheduler = activity
    }
}
