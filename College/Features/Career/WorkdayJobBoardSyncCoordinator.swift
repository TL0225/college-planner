// WorkdayJobBoardSyncCoordinator.swift
// Feature: Career
// Purpose: Career module — WorkdayJobBoardSyncCoordinator.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import Combine

@MainActor
final class WorkdayJobBoardSyncCoordinator: ObservableObject {
    static let shared = WorkdayJobBoardSyncCoordinator()

    private static let lastSuccessfulSyncKey = "workday.lastSuccessfulSyncAt"
    private static let lastOpeningsViewedKey = "workday.lastOpeningsViewedAt"

    @Published private(set) var uiState: WorkdaySyncUIState = .empty

    private var lastScrapeStartedAt: Date?
    private var scrapeQueue: [WorkdayCompanyConfigEntry] = []
    private var queueProcessorTask: Task<Void, Never>?
    private(set) var currentlyScrapingSlug: String?
    private var didStart = false

    private init() {
        rebuildIdleUIState()
    }

    func start() {
        guard !didStart else { return }
        didStart = true
        WorkdayRefreshScheduler.shared.start()
        rebuildIdleUIState()
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

    func scrapeAllEnabledCompanies() async {
        let companies = WorkdayCompaniesStore.shared.enabledCompanies
        guard !companies.isEmpty else { return }
        enqueue(companies)
        await processQueue()
    }

    func scrapeCompany(_ company: WorkdayCompanyConfigEntry) async {
        enqueue([company])
        await processQueue()
    }

    private func enqueue(_ companies: [WorkdayCompanyConfigEntry]) {
        for company in companies {
            if !scrapeQueue.contains(where: { $0.id == company.id }) {
                scrapeQueue.append(company)
            }
        }
        syncInFlightFlag()
    }

    private func setCompanyStatus(slug: String, status: WorkdaySyncUIState.CompanyState.Status) {
        if let idx = uiState.companies.firstIndex(where: { $0.slug == slug }) {
            uiState.companies[idx].status = status
        }
        syncInFlightFlag()
    }

    private func syncInFlightFlag() {
        uiState.isAnyScrapeInFlight = currentlyScrapingSlug != nil
    }

    private func updateScrapeProgress(slug: String, completed: Int, total: Int?) {
        guard currentlyScrapingSlug == slug else { return }
        let progress: Double?
        if let total, total > 0 {
            progress = min(1, Double(completed) / Double(total))
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
                if let last = lastScrapeStartedAt {
                    let elapsed = Date().timeIntervalSince(last)
                    if elapsed < WorkdayJobBoardThresholds.minScrapeCooldown {
                        let wait = WorkdayJobBoardThresholds.minScrapeCooldown - elapsed
                        try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
                    }
                }

                let company = scrapeQueue.removeFirst()
                let slug = company.normalizedSlug
                currentlyScrapingSlug = slug
                lastScrapeStartedAt = Date()
                setCompanyStatus(slug: slug, status: .scraping(progress: nil))
                await runScrape(for: company)
                currentlyScrapingSlug = nil
            }

            postImportFinished()
            }
        }
        await queueProcessorTask?.value
    }

    private func runScrape(for company: WorkdayCompanyConfigEntry) async {
        let slug = company.normalizedSlug
        let reportProgress: @Sendable (Int, Int?) -> Void = { [weak self] completed, total in
            Task { @MainActor in
                self?.updateScrapeProgress(slug: slug, completed: completed, total: total)
            }
        }

        do {
            let scraper = JobBoardScraperRegistry.scraper(for: company.platform)
            let listings = try await scraper.scrapeListings(for: company, reportProgress: reportProgress)
            let count = await CollegePersistence.shared.importJobBoardListings(
                company: company,
                listings: listings
            )
            let at = Date()
            WorkdayRefreshScheduler.recordLastScraped(slug: slug, at: at)
            updateCompanyState(slug: slug, status: .ok(jobCount: count, at: at))
            UserDefaults.standard.set(at, forKey: Self.lastSuccessfulSyncKey)
            uiState.lastSuccessfulSyncAt = at
            await JobBoardNotificationService.shared.notifyIfNeeded(
                company: company,
                newCount: count
            )
        } catch let error as JobBoardScraperError {
            WorkdayRefreshScheduler.recordLastAttempted(slug: slug)
            updateCompanyState(slug: slug, status: .error(error.asWorkdayError, at: Date()))
        } catch let error as WorkdayScraperError {
            WorkdayRefreshScheduler.recordLastAttempted(slug: slug)
            updateCompanyState(slug: slug, status: .error(error, at: Date()))
        } catch {
            WorkdayRefreshScheduler.recordLastAttempted(slug: slug)
            updateCompanyState(slug: slug, status: .error(.decodingFailed(error.localizedDescription), at: Date()))
        }
    }

    private func updateCompanyState(slug: String, status: WorkdaySyncUIState.CompanyState.Status) {
        if let idx = uiState.companies.firstIndex(where: { $0.slug == slug }) {
            uiState.companies[idx].status = status
        }
        syncInFlightFlag()
    }

    func rebuildIdleUIState() {
        let companies = WorkdayCompaniesStore.shared.companies
        let previousBySlug = Dictionary(uniqueKeysWithValues: uiState.companies.map { ($0.slug, $0) })
        uiState.companies = companies.map { entry in
            let slug = entry.normalizedSlug
            if currentlyScrapingSlug == slug {
                return WorkdaySyncUIState.CompanyState(
                    slug: slug,
                    displayName: entry.displayName,
                    status: .scraping(progress: nil)
                )
            }
            let last = WorkdayRefreshScheduler.lastScraped(slug: slug)
            let status: WorkdaySyncUIState.CompanyState.Status
            if let last {
                let count: Int
                if case .ok(let cachedCount, _) = previousBySlug[slug]?.status {
                    count = cachedCount
                } else {
                    count = Self.activeJobCount(slug: slug)
                }
                status = .ok(jobCount: count, at: last)
            } else {
                status = .idle
            }
            return WorkdaySyncUIState.CompanyState(
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

    private static func activeJobCount(slug: String) -> Int {
        (try? AppDataStore.shared.careerRepository.activePostingCount(companySlug: slug)) ?? 0
    }

    private func postImportFinished() {
        rebuildIdleUIState()
        NotificationCenter.default.post(name: .workdayImportDidFinish, object: nil)
    }
}
