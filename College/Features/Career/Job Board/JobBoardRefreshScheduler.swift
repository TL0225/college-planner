// JobBoardRefreshScheduler.swift
// Feature: Career
// Purpose: Career module — JobBoardRefreshScheduler.
// Data: CollegePersistence / repositories when applicable.

import AppKit
import Foundation

/// Schedules periodic job-board list scrapes on macOS (best-effort; macOS may defer fires).
@MainActor
final class JobBoardRefreshScheduler {
    static let shared = JobBoardRefreshScheduler()

    static let refreshIntervalStorageKey = "workday.refreshInterval"

    private let scheduler = BackgroundServiceScheduler(identifier: BackgroundServiceSchedulerIDs.jobBoardRefresh)
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
        Task { @MainActor in
            JobBoardSyncCoordinator.shared.rebuildIdleUIState()
            await refreshOverdueCompaniesIfNeeded()
        }
    }

    func stop() {
        scheduler.invalidate()
        if let becameActiveObserver {
            NotificationCenter.default.removeObserver(becameActiveObserver)
            self.becameActiveObserver = nil
        }
        didStart = false
    }

    func reschedule() {
        scheduler.invalidate()
        registerBackgroundScheduler()
    }

    var selectedIntervalSeconds: TimeInterval {
        guard UserDefaults.standard.object(forKey: Self.refreshIntervalStorageKey) != nil else {
            return JobBoardThresholds.defaultRefreshInterval
        }
        let stored = UserDefaults.standard.integer(forKey: Self.refreshIntervalStorageKey)
        if stored == JobBoardRefreshIntervalOption.manual.rawValue { return 0 }
        return TimeInterval(stored)
    }

    var isManualOnly: Bool {
        guard UserDefaults.standard.object(forKey: Self.refreshIntervalStorageKey) != nil else { return false }
        return UserDefaults.standard.integer(forKey: Self.refreshIntervalStorageKey) == JobBoardRefreshIntervalOption.manual.rawValue
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

        let store = JobBoardCompaniesStore.shared
        for company in store.enabledCompanies {
            guard shouldAutoRefresh(slug: company.normalizedSlug, now: now, interval: interval) else {
                continue
            }
            await JobBoardSyncCoordinator.shared.scrapeCompany(company)
        }
    }

    /// Whether an automatic scrape is due for `slug` (manual scrape bypasses this).
    func shouldAutoRefresh(
        slug: String,
        now: Date = Date(),
        interval: TimeInterval? = nil
    ) -> Bool {
        guard !isManualOnly else { return false }
        let refreshInterval = interval ?? selectedIntervalSeconds
        guard refreshInterval > 0 else { return false }

        if JobBoardSyncCoordinator.shared.isScraping(slug: slug) {
            return false
        }
        if Self.isInFailureBackoff(slug: slug) {
            return false
        }

        if let last = Self.effectiveLastScraped(slug: slug) {
            return now.timeIntervalSince(last) >= refreshInterval
        }

        // Never scraped and no cached listings — first sync only.
        return !JobBoardSyncCoordinator.hasCachedPostings(slug: slug)
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

    static func lastSyncErrorKey(slug: String) -> String {
        "workday.lastSyncError.\(slug)"
    }

    static func recordLastScraped(slug: String, at date: Date = Date()) {
        UserDefaults.standard.set(date, forKey: lastScrapedKey(slug: slug))
        // A successful scrape also counts as an attempt; clear any separate attempt marker.
        UserDefaults.standard.removeObject(forKey: lastAttemptedKey(slug: slug))
        clearLastSyncError(slug: slug)
    }

    /// Call when a scrape fails so the scheduler backs off instead of retrying immediately.
    static func recordLastAttempted(slug: String, at date: Date = Date()) {
        UserDefaults.standard.set(date, forKey: lastAttemptedKey(slug: slug))
    }

    static func recordLastSyncError(slug: String, message: String) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        UserDefaults.standard.set(trimmed, forKey: lastSyncErrorKey(slug: slug))
    }

    static func lastSyncError(slug: String) -> String? {
        let raw = UserDefaults.standard.string(forKey: lastSyncErrorKey(slug: slug))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let raw, !raw.isEmpty else { return nil }
        return raw
    }

    static func clearLastSyncError(slug: String) {
        UserDefaults.standard.removeObject(forKey: lastSyncErrorKey(slug: slug))
    }

    static func persistedFailureStatus(slug: String) -> JobBoardSyncUIState.CompanyState.Status? {
        guard effectiveLastScraped(slug: slug) == nil else { return nil }
        guard JobBoardSyncCoordinator.activeJobCount(slug: slug) == 0 else { return nil }
        guard let message = lastSyncError(slug: slug) else { return nil }
        let at = UserDefaults.standard.object(forKey: lastAttemptedKey(slug: slug)) as? Date ?? Date()
        return .error(.decodingFailed(message), at: at)
    }

    static func lastScraped(slug: String) -> Date? {
        UserDefaults.standard.object(forKey: lastScrapedKey(slug: slug)) as? Date
    }

    /// UserDefaults timestamp, falling back to persisted posting scrape dates.
    static func effectiveLastScraped(slug: String) -> Date? {
        if let stored = lastScraped(slug: slug) {
            return stored
        }
        guard let persisted = JobBoardSyncCoordinator.persistedLastScrapeDate(slug: slug) else {
            return nil
        }
        recordLastScraped(slug: slug, at: persisted)
        return persisted
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

        scheduler.configure(
            repeats: true,
            interval: intervalSeconds,
            tolerance: intervalSeconds * 0.2,
            qualityOfService: .utility
        )
        scheduler.start { [weak self] completion in
            await self?.refreshOverdueCompaniesIfNeeded()
            completion(.finished)
        }
    }
}
