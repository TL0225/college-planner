// JobBoardSyncCoordinator.swift
// Feature: Career
// Purpose: Career module — JobBoardSyncCoordinator.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import Combine

@MainActor
final class JobBoardSyncCoordinator: ObservableObject {
    static let shared = JobBoardSyncCoordinator()

    private static let lastSuccessfulSyncKey = "workday.lastSuccessfulSyncAt"
    private static let lastOpeningsViewedKey = "workday.lastOpeningsViewedAt"

    @Published private(set) var uiState: JobBoardSyncUIState = .empty

    private var lastScrapeStartedAt: Date?
    private var scrapeQueue: [QueuedCompanyScrape] = []
    private var queueProcessorTask: Task<Void, Never>?
    private(set) var currentlyScrapingSlug: String?
    private var didStart = false

    private init() {
        rebuildIdleUIState()
    }

    func start() {
        guard !didStart else { return }
        didStart = true
        rebuildIdleUIState()
        JobBoardRefreshScheduler.shared.start()
        Task { await JobBoardNotificationService.shared.requestPermissionIfNeeded() }
    }

    func markOpeningsViewed() {
        UserDefaults.standard.set(Date(), forKey: Self.lastOpeningsViewedKey)
    }

    func newOpeningsCount(using persistence: CollegePersistence = .shared) -> Int {
        let lastViewed = UserDefaults.standard.object(forKey: Self.lastOpeningsViewedKey) as? Date
        return persistence.countNewOpeningsSince(lastViewed)
    }

    func isScraping(slug: String) -> Bool {
        currentlyScrapingSlug == slug
    }

    func scrapeAllEnabledCompanies(force: Bool = false) async {
        let companies = JobBoardCompaniesStore.shared.enabledCompanies
        guard !companies.isEmpty else { return }
        if force {
            enqueue(companies, force: true)
        } else {
            for company in companies {
                await scrapeCompany(company, force: false)
            }
            return
        }
        await processQueue()
    }

    func scrapeCompany(_ company: JobBoardCompany, force: Bool = false) async {
        let slug = company.normalizedSlug
        if force, isScraping(slug: slug) {
            await restartInFlightScrape(for: company)
            return
        }
        if !force {
            if isScraping(slug: slug) { return }
            guard !JobBoardRefreshScheduler.shared.isManualOnly else { return }
            let interval = JobBoardRefreshScheduler.shared.selectedIntervalSeconds
            if interval > 0 {
                if Self.hasCachedPostings(slug: slug),
                   JobBoardRefreshScheduler.effectiveLastScraped(slug: slug) == nil {
                    let at = Self.persistedLastScrapeDate(slug: slug) ?? Date()
                    JobBoardRefreshScheduler.recordLastScraped(slug: slug, at: at)
                }
                if let last = JobBoardRefreshScheduler.effectiveLastScraped(slug: slug),
                   Date().timeIntervalSince(last) < interval {
                    return
                }
            }
        }
        enqueue([company], force: force)
        await processQueue()
    }

    private struct QueuedCompanyScrape: Equatable {
        let company: JobBoardCompany
        var force: Bool
    }

    /// Cancels the active scrape for `company` and re-queues it at the front (manual "Scrape now").
    private func restartInFlightScrape(for company: JobBoardCompany) async {
        queueProcessorTask?.cancel()
        await queueProcessorTask?.value
        scrapeQueue.removeAll { $0.company.id == company.id }
        scrapeQueue.insert(QueuedCompanyScrape(company: company, force: true), at: 0)
        currentlyScrapingSlug = nil
        syncInFlightFlag()
        await processQueue()
    }

    /// True when local store already has active listings for this company.
    static func hasCachedPostings(slug: String) -> Bool {
        activeJobCount(slug: slug) > 0
    }

    /// Quick check is safe only when the board fingerprint matches and local active rows align with the board total.
    static func canQuickCheckSkipFullScrape(
        probe: JobBoardBoardProbeResult,
        stored: JobBoardBoardFingerprint,
        slug: String
    ) -> Bool {
        guard probe.fingerprint == stored else { return false }
        let localActive = activeJobCount(slug: slug)
        guard localActive == stored.boardTotal else { return false }
        return true
    }

    /// Latest `lastScrapedAt` from persisted postings for `slug`.
    static func persistedLastScrapeDate(slug: String) -> Date? {
        latestPostingScrapeDate(slug: slug)
    }

    private func enqueue(_ companies: [JobBoardCompany], force: Bool = false) {
        for company in companies {
            if let index = scrapeQueue.firstIndex(where: { $0.company.id == company.id }) {
                if force { scrapeQueue[index].force = true }
            } else {
                scrapeQueue.append(QueuedCompanyScrape(company: company, force: force))
            }
        }
        syncInFlightFlag()
    }

    private func setCompanyStatus(slug: String, status: JobBoardSyncUIState.CompanyState.Status) {
        if let idx = uiState.companies.firstIndex(where: { $0.slug == slug }) {
            uiState.companies[idx].status = status
        }
        syncInFlightFlag()
        syncBackgroundActivity(slug: slug, status: status)
    }

    private func syncInFlightFlag() {
        uiState.isAnyScrapeInFlight = currentlyScrapingSlug != nil
    }

    private func updateScrapeProgress(slug: String, completed: Int, total: Int?) {
        guard currentlyScrapingSlug == slug else { return }
        let progress: Double?
        if let total, total > 0 {
            // Cap at 99% until listings are saved locally — avoids a stuck "100%" UI.
            progress = min(0.99, Double(completed) / Double(total))
        } else {
            progress = nil
        }
        setCompanyStatus(slug: slug, status: .scraping(progress: progress))
    }

    private func processQueue() async {
        if queueProcessorTask == nil || queueProcessorTask?.isCancelled == true {
            queueProcessorTask = Task { @MainActor in
            defer {
                queueProcessorTask = nil
                currentlyScrapingSlug = nil
                syncInFlightFlag()
            }

            while !scrapeQueue.isEmpty {
                if Task.isCancelled { break }
                if let last = lastScrapeStartedAt {
                    let elapsed = Date().timeIntervalSince(last)
                    if elapsed < JobBoardThresholds.minScrapeCooldown {
                        let wait = JobBoardThresholds.minScrapeCooldown - elapsed
                        try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
                    }
                }

                let queued = scrapeQueue.removeFirst()
                let company = queued.company
                let slug = company.normalizedSlug
                currentlyScrapingSlug = slug
                lastScrapeStartedAt = Date()
                setCompanyStatus(slug: slug, status: .scraping(progress: nil))
                await runScrape(for: company, force: queued.force)
                currentlyScrapingSlug = nil
            }

            postImportFinished()
            }
        }
        await queueProcessorTask?.value
    }

    private func runScrape(for company: JobBoardCompany, force: Bool) async {
        let slug = company.normalizedSlug
        let reportProgress: @Sendable (Int, Int?) -> Void = { [weak self] completed, total in
            Task { @MainActor in
                self?.updateScrapeProgress(slug: slug, completed: completed, total: total)
            }
        }

        do {
            let scraper = JobBoardScraperRegistry.scraper(for: company.platform)

            if !force,
               Self.hasCachedPostings(slug: slug),
               !JobBoardBoardFingerprintStore.isDueForFullListScrape(slug: slug),
               let probe = try await scraper.probeBoardFingerprint(for: company),
               let stored = JobBoardBoardFingerprintStore.storedFingerprint(slug: slug),
               Self.canQuickCheckSkipFullScrape(probe: probe, stored: stored, slug: slug) {
                await completeQuickBoardCheck(company: company, slug: slug)
                return
            }

            CollegePersistence.shared.beginJobBoardListImport(company: company)
            var importFinalized = false
            defer {
                if !importFinalized {
                    CollegePersistence.shared.discardJobBoardListImport(companySlug: slug)
                }
            }
            let listings = try await scraper.scrapeListings(
                for: company,
                reportProgress: reportProgress,
                onListingsPage: { page in
                    do {
                        try await CollegePersistence.shared.mergeJobBoardListImportPage(
                            companySlug: slug,
                            listings: page
                        )
                    } catch {
                        DebugLogger.shared.log(
                            "Job board page import failed for \(company.displayName): \(error.localizedDescription)",
                            category: .scraper,
                            level: .error
                        )
                    }
                }
            )
            if listings.isEmpty, Self.hasCachedPostings(slug: slug) {
                throw JobBoardScraperError.decodingFailed(
                    "Scrape returned no listings — existing openings were kept."
                )
            }
            setCompanyStatus(slug: slug, status: .importing)
            let count: Int
            if CollegePersistence.shared.jobBoardListImportHasMergedPages(companySlug: slug) {
                count = try await CollegePersistence.shared.finalizeJobBoardListImport(companySlug: slug)
                importFinalized = true
            } else {
                CollegePersistence.shared.discardJobBoardListImport(companySlug: slug)
                count = try CollegePersistence.shared.importJobBoardListings(
                    company: company,
                    listings: listings
                )
                importFinalized = true
            }
            await recordFullListScrapeFingerprint(company: company, scraper: scraper, slug: slug)
            let at = Date()
            JobBoardRefreshScheduler.recordLastScraped(slug: slug, at: at)
            updateCompanyState(slug: slug, status: .ok(jobCount: count, at: at))
            UserDefaults.standard.set(at, forKey: Self.lastSuccessfulSyncKey)
            uiState.lastSuccessfulSyncAt = at
            await JobBoardNotificationService.shared.notifyIfNeeded(company: company)
        } catch is CancellationError {
            JobBoardRefreshScheduler.recordLastAttempted(slug: slug)
            JobBoardRefreshScheduler.recordLastSyncError(
                slug: slug,
                message: "Sync was interrupted. Try again when you have a stable connection."
            )
            return
        } catch let error as JobBoardScraperError {
            JobBoardRefreshScheduler.recordLastAttempted(slug: slug)
            let mapped = error.asWorkdayError
            DebugLogger.shared.log(
                "Job board scrape failed for \(company.displayName): \(mapped.displayMessage)",
                category: .scraper,
                level: .error
            )
            recordSyncFailure(slug: slug, error: mapped)
            updateCompanyState(slug: slug, status: .error(mapped, at: Date()))
        } catch let error as WorkdayScraperError {
            JobBoardRefreshScheduler.recordLastAttempted(slug: slug)
            DebugLogger.shared.log(
                "Job board scrape failed for \(company.displayName): \(error.displayMessage)",
                category: .scraper,
                level: .error
            )
            recordSyncFailure(slug: slug, error: error)
            updateCompanyState(slug: slug, status: .error(error, at: Date()))
        } catch {
            JobBoardRefreshScheduler.recordLastAttempted(slug: slug)
            let mapped = WorkdayScraperError.decodingFailed(error.localizedDescription)
            DebugLogger.shared.log(
                "Job board scrape failed for \(company.displayName): \(error.localizedDescription)",
                category: .scraper,
                level: .error
            )
            recordSyncFailure(slug: slug, error: mapped)
            updateCompanyState(slug: slug, status: .error(mapped, at: Date()))
        }
    }

    private func recordSyncFailure(slug: String, error: WorkdayScraperError) {
        JobBoardRefreshScheduler.recordLastSyncError(slug: slug, message: error.displayMessage)
    }

    private func completeQuickBoardCheck(company: JobBoardCompany, slug: String) async {
        CollegePersistence.shared.touchActiveJobBoardPostings(companySlug: slug)
        let at = Date()
        JobBoardRefreshScheduler.recordLastScraped(slug: slug, at: at)
        let count = Self.activeJobCount(slug: slug)
        updateCompanyState(slug: slug, status: .ok(jobCount: count, at: at))
        UserDefaults.standard.set(at, forKey: Self.lastSuccessfulSyncKey)
        uiState.lastSuccessfulSyncAt = at
        DebugLogger.shared.log(
            "Quick board check unchanged for \(company.displayName) — skipped full pagination",
            category: .scraper,
            level: .info
        )
    }

    private func recordFullListScrapeFingerprint(
        company: JobBoardCompany,
        scraper: any JobBoardScraper,
        slug: String
    ) async {
        if let probe = try? await scraper.probeBoardFingerprint(for: company) {
            JobBoardBoardFingerprintStore.recordFingerprint(probe.fingerprint, slug: slug)
        }
        JobBoardBoardFingerprintStore.recordFullListScrape(slug: slug)
    }

    private func updateCompanyState(slug: String, status: JobBoardSyncUIState.CompanyState.Status) {
        if let idx = uiState.companies.firstIndex(where: { $0.slug == slug }) {
            uiState.companies[idx].status = status
        }
        syncInFlightFlag()
        syncBackgroundActivity(slug: slug, status: status)
    }

    private func syncBackgroundActivity(
        slug: String,
        status: JobBoardSyncUIState.CompanyState.Status
    ) {
        let activityID = BackgroundActivityCenter.jobBoardActivityID(slug: slug)
        let displayName = uiState.companies.first(where: { $0.slug == slug })?.displayName
            ?? JobBoardCompaniesStore.shared.companies.first(where: { $0.normalizedSlug == slug })?.displayName
            ?? slug

        switch status {
        case .idle:
            BackgroundActivityReporter.remove(id: activityID)
        case .scraping(let progress):
            BackgroundActivityReporter.running(
                id: activityID,
                domain: .careerJobBoard,
                title: displayName,
                detail: String(localized: "jobboard.background.downloading", defaultValue: "Downloading openings…"),
                fraction: progress,
                indeterminate: progress == nil
            )
        case .importing:
            BackgroundActivityReporter.running(
                id: activityID,
                domain: .careerJobBoard,
                title: displayName,
                detail: String(localized: "jobboard.background.saving", defaultValue: "Saving listings…"),
                fraction: 0.99,
                indeterminate: false
            )
        case .ok(let count, _):
            BackgroundActivityReporter.finish(
                id: activityID,
                succeeded: true,
                summary: count == 0
                    ? String(localized: "jobboard.background.no_openings", defaultValue: "No active openings")
                    : String(format: String(localized: "jobboard.background.synced", defaultValue: "%d openings synced"), count)
            )
        case .error(let err, _):
            BackgroundActivityReporter.finish(
                id: activityID,
                succeeded: false,
                summary: err.displayMessage
            )
        }
    }

    func rebuildIdleUIState() {
        let companies = JobBoardCompaniesStore.shared.companies
        let previousBySlug = Dictionary(uniqueKeysWithValues: uiState.companies.map { ($0.slug, $0) })
        uiState.companies = companies.map { entry in
            let slug = entry.normalizedSlug
            if currentlyScrapingSlug == slug {
                return JobBoardSyncUIState.CompanyState(
                    slug: slug,
                    displayName: entry.displayName,
                    status: .scraping(progress: nil)
                )
            }
            if case .importing = previousBySlug[slug]?.status {
                return JobBoardSyncUIState.CompanyState(
                    slug: slug,
                    displayName: entry.displayName,
                    status: .importing
                )
            }
            if case .error(let err, let at) = previousBySlug[slug]?.status,
               JobBoardRefreshScheduler.effectiveLastScraped(slug: slug) == nil,
               Self.activeJobCount(slug: slug) == 0 {
                return JobBoardSyncUIState.CompanyState(
                    slug: slug,
                    displayName: entry.displayName,
                    status: .error(err, at: at)
                )
            }
            let last = JobBoardRefreshScheduler.effectiveLastScraped(slug: slug)
            let status: JobBoardSyncUIState.CompanyState.Status
            if let last {
                let count: Int
                if case .ok(let cachedCount, _) = previousBySlug[slug]?.status {
                    count = cachedCount
                } else {
                    count = Self.activeJobCount(slug: slug)
                }
                status = .ok(jobCount: count, at: last)
            } else {
                let count = Self.activeJobCount(slug: slug)
                if count > 0 {
                    let at = Self.latestPostingScrapeDate(slug: slug) ?? Date()
                    JobBoardRefreshScheduler.recordLastScraped(slug: slug, at: at)
                    status = .ok(jobCount: count, at: at)
                } else if let persistedFailure = JobBoardRefreshScheduler.persistedFailureStatus(slug: slug) {
                    status = persistedFailure
                } else {
                    status = .idle
                }
            }
            return JobBoardSyncUIState.CompanyState(
                slug: slug,
                displayName: entry.displayName,
                status: status
            )
        }
        uiState.lastSuccessfulSyncAt = UserDefaults.standard.object(forKey: Self.lastSuccessfulSyncKey) as? Date
        if currentlyScrapingSlug == nil {
            uiState.isAnyScrapeInFlight = false
        }
    }

    static func activeJobCount(slug: String) -> Int {
        (try? AppDataStore.shared.careerRepository.activePostingCount(companySlug: slug)) ?? 0
    }

    private static func latestPostingScrapeDate(slug: String) -> Date? {
        let repo = AppDataStore.shared.careerRepository
        guard let postings = try? repo.fetchCompanyPostings(companySlug: slug) else { return nil }
        return postings.compactMap(\.lastScrapedAt).max()
    }

    private func postImportFinished() {
        rebuildIdleUIState()
        NotificationCenter.default.post(name: .jobBoardImportDidFinish, object: nil)
    }
}
