// LaunchPreloadCoordinator.swift
// Feature: App
// Purpose: App module — FeaturePreloadDescriptor.
// Data: CollegePersistence / repositories when applicable.

import CollegeCalendar
import Foundation
import Observation

@Observable
@MainActor
final class LaunchPreloadCoordinator {
    enum StepID: CaseIterable {
        case storeReady
        case coreSnapshots
        case calendarWarmup
        case lmsWarmup
        case integrationsWarmup
        case featureWarmup
    }

    enum FeatureCriticality {
        case requiredBeforeReady
        case bestEffort
    }

    enum FeatureOutcome: String {
        case completed
        case timedOut
        case skippedByBudget
        case failed
    }

    struct FeaturePreloadDescriptor {
        let id: String
        let title: String
        let criticality: FeatureCriticality
        let timeoutSeconds: TimeInterval
        let retryLimit: Int
        let run: (
            _ context: FeaturePreloadContext,
            _ onProgress: @escaping (Double) -> Void,
            _ onDetail: @escaping (String) -> Void
        ) async throws -> Void
    }

    struct FeaturePreloadContext {
        let collegePersistence: CollegePersistence
        let calendarManager: CalendarIntegrationManager
        let lmsCoordinator: LMSWebCoordinator
        let cloudIntegration: CloudIntegrationService
    }

    private(set) var isRunning: Bool = false
    private(set) var isCompleted: Bool = false
    private(set) var overallProgress: Double = 0
    private(set) var currentStepTitle: String = "Starting"
    private(set) var statusText: String = "Preparing startup..."
    private(set) var currentStepDetailText: String = ""
    private(set) var currentStepProgress: Double = 0
    private(set) var currentStepNumber: Int = 0
    private(set) var totalStepCount: Int = StepID.allCases.count
    private(set) var retryAttempt: Int = 0
    private(set) var lastErrorText: String? = nil
    private(set) var etaText: String? = nil
    private(set) var featureOutcomes: [String: FeatureOutcome] = [:]

    private var preloadTask: Task<Void, Never>?
    private var stepProgress: [StepID: Double] = [:]
    private var activeStepID: StepID?
    private var progressSamples: [(time: Date, progress: Double)] = []
    private var launchStartedAt: Date?

    nonisolated(unsafe) private static var featureRegistry: [String: FeaturePreloadDescriptor] = [:]
    nonisolated(unsafe) private static var didBootstrapBuiltIns: Bool = false

    private let featureWarmupBudgetSeconds: TimeInterval = 3

    private let stepWeights: [StepID: Double] = [
        .storeReady: 0.20,
        .coreSnapshots: 0.18,
        .calendarWarmup: 0.20,
        .lmsWarmup: 0.18,
        .integrationsWarmup: 0.12,
        .featureWarmup: 0.12,
    ]

    nonisolated deinit {
        MainActor.assumeIsolated {
            preloadTask?.cancel()
        }
    }

    func startIfNeeded(
        collegePersistence: CollegePersistence,
        calendarManager: CalendarIntegrationManager,
        lmsCoordinator: LMSWebCoordinator,
        cloudIntegration: CloudIntegrationService
    ) {
        guard preloadTask == nil, !isCompleted else { return }
        launchStartedAt = Date()

        Self.bootstrapBuiltInFeaturePreloadsIfNeeded()

        isRunning = true
        currentStepTitle = "Preparing startup"
        statusText = "Initializing preload pipeline..."
        currentStepDetailText = ""
        currentStepProgress = 0
        currentStepNumber = 0
        retryAttempt = 0
        lastErrorText = nil
        etaText = nil
        progressSamples.removeAll()
        overallProgress = 0
        featureOutcomes = [:]

        preloadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.runPipeline(
                collegePersistence: collegePersistence,
                calendarManager: calendarManager,
                lmsCoordinator: lmsCoordinator,
                cloudIntegration: cloudIntegration
            )
        }
    }

    private func runPipeline(
        collegePersistence: CollegePersistence,
        calendarManager: CalendarIntegrationManager,
        lmsCoordinator: LMSWebCoordinator,
        cloudIntegration: CloudIntegrationService
    ) async {
        await runRetriableStep(
            id: .storeReady,
            title: "Loading local database",
            retriesUntilSuccess: true
        ) { [weak self] in
            guard let self else { return }
            await self.waitForStoreLoaded(collegePersistence)
        }

        await runRetriableStep(
            id: .coreSnapshots,
            title: "Warming local data",
            retriesUntilSuccess: true
        ) {
            LaunchBootstrapCache.fetchSemestersIfNeeded()
            self.setStepProgress(.coreSnapshots, progress: 0.25)

            LaunchBootstrapCache.fetchPlansIfNeeded()
            self.setStepProgress(.coreSnapshots, progress: 0.50)

            LaunchBootstrapCache.fetchProfileIfNeeded()
            self.setStepProgress(.coreSnapshots, progress: 0.75)

            LaunchBootstrapCache.fetchVaultDocumentsIfNeeded()
            self.setStepProgress(.coreSnapshots, progress: 1)
            AppDataStoreLaunchWarmup.prepareIfNeeded()
        }

        await runRetriableStep(
            id: .calendarWarmup,
            title: "Preloading calendar",
            retriesUntilSuccess: true
        ) {
            try await calendarManager.preloadForLaunch { progress in
                self.setStepProgress(.calendarWarmup, progress: progress)
            } detail: { detail in
                self.setStepDetail(.calendarWarmup, detail: detail)
            }
            self.setStepProgress(.calendarWarmup, progress: 1)
        }

        await runRetriableStep(
            id: .lmsWarmup,
            title: String(localized: "lms.preload.title", defaultValue: "Preloading Learning Management System"),
            retriesUntilSuccess: true
        ) {
            guard LMSPortalConfiguration.shouldPreloadPortalAtLaunch() else {
                self.setStepDetail(.lmsWarmup, detail: "Skipped — LMS portal opens on first visit")
                self.setStepProgress(.lmsWarmup, progress: 1)
                return
            }
            try await lmsCoordinator.preloadPortalForLaunch { progress in
                self.setStepProgress(.lmsWarmup, progress: progress)
            } detail: { detail in
                self.setStepDetail(.lmsWarmup, detail: detail)
            }
            self.setStepProgress(.lmsWarmup, progress: 1)
        }

        await runRetriableStep(
            id: .integrationsWarmup,
            title: "Scanning integrations",
            retriesUntilSuccess: true
        ) {
            await cloudIntegration.preloadForLaunch { progress in
                self.setStepProgress(.integrationsWarmup, progress: progress)
            } detail: { detail in
                self.setStepDetail(.integrationsWarmup, detail: detail)
            }
            self.setStepProgress(.integrationsWarmup, progress: 1)
        }

        await runRetriableStep(
            id: .featureWarmup,
            title: "Warming app features",
            retriesUntilSuccess: false
        ) {
            await self.runRegisteredFeaturePreloads(
                context: FeaturePreloadContext(
                    collegePersistence: collegePersistence,
                    calendarManager: calendarManager,
                    lmsCoordinator: lmsCoordinator,
                    cloudIntegration: cloudIntegration
                )
            )
        }

        currentStepTitle = "Startup ready"
        statusText = "Finished preloading"
        currentStepDetailText = "All startup steps completed"
        currentStepProgress = 1
        currentStepNumber = totalStepCount
        retryAttempt = 0
        lastErrorText = nil
        etaText = nil
        overallProgress = 1
        isCompleted = true
        isRunning = false
        if let launchStartedAt {
            let ms = Int(Date().timeIntervalSince(launchStartedAt) * 1000)
            SnowLeopardHealthMetrics.recordColdLaunch(milliseconds: Double(ms))
            Task {
                await LoadOperationTrace.recordCompleted(
                    name: "LaunchPipeline",
                    category: .launch,
                    durationMs: ms,
                    budgetMs: LaunchPerformanceAcceptance.pipelineWallClockWarnThresholdMs,
                    executionContext: .mainThread,
                    metadata: [
                        "features": featureOutcomes
                            .map { "\($0.key)=\($0.value.rawValue)" }
                            .sorted()
                            .joined(separator: ",")
                    ]
                )
            }
        }
    }

    private func runRegisteredFeaturePreloads(context: FeaturePreloadContext) async {
        let all = Self.featureRegistry.values.sorted { lhs, rhs in
            if lhs.criticality == rhs.criticality {
                return lhs.id < rhs.id
            }
            return lhs.criticality == .requiredBeforeReady && rhs.criticality == .bestEffort
        }

        guard !all.isEmpty else {
            setStepDetail(.featureWarmup, detail: "No feature preload descriptors registered")
            setStepProgress(.featureWarmup, progress: 1)
            return
        }

        auditPreloadCoverage(registeredIDs: Set(all.map(\.id)))

        let deadline = Date().addingTimeInterval(featureWarmupBudgetSeconds)
        let total = max(1, all.count)

        for (index, descriptor) in all.enumerated() {
            let startFraction = Double(index) / Double(total)
            let endFraction = Double(index + 1) / Double(total)

            if descriptor.criticality == .bestEffort, Date() > deadline {
                featureOutcomes[descriptor.id] = .skippedByBudget
                setStepDetail(.featureWarmup, detail: "Skipped \(descriptor.title) due to startup budget")
                setStepProgress(.featureWarmup, progress: endFraction)
                continue
            }

            var attempt = 0
            var completed = false

            while attempt <= max(0, descriptor.retryLimit), !completed {
                do {
                    setStepDetail(.featureWarmup, detail: "\(descriptor.title) (attempt \(attempt + 1))")

                    try await descriptor.run(
                        context,
                        { progress in
                            let clamped = min(1, max(0, progress))
                            let mapped = startFraction + ((endFraction - startFraction) * clamped)
                            self.setStepProgress(.featureWarmup, progress: mapped)
                        },
                        { detail in
                            self.setStepDetail(.featureWarmup, detail: detail)
                        }
                    )

                    featureOutcomes[descriptor.id] = .completed
                    completed = true
                } catch {
                    if attempt >= descriptor.retryLimit {
                        featureOutcomes[descriptor.id] = .failed
                        break
                    }
                    attempt += 1
                }
            }

            setStepProgress(.featureWarmup, progress: endFraction)
        }

        setStepProgress(.featureWarmup, progress: 1)
    }

    private func auditPreloadCoverage(registeredIDs: Set<String>) {
        let expected = Set(AppPage.preloadCoverageFeatureIDs)
        let missing = expected.subtracting(registeredIDs)
        guard !missing.isEmpty else { return }

        let detail = "Missing preload descriptors for: \(missing.sorted().joined(separator: ", "))"
        DebugLogger.shared.log(detail, category: .app, level: .warn)
    }

    static func registerFeaturePreload(_ descriptor: FeaturePreloadDescriptor) {
        featureRegistry[descriptor.id] = descriptor
    }

    static func bootstrapBuiltInFeaturePreloadsIfNeeded() {
        guard !didBootstrapBuiltIns else { return }
        didBootstrapBuiltIns = true

        // Module-owned registration hooks. Add new feature hooks in feature files.
        OverviewFeaturePreloadRegistration.register()
        AcademicsFeaturePreloadRegistration.register()
        CareerFeaturePreloadRegistration.register()
        CalendarFeaturePreloadRegistration.register()
        LMSFeaturePreloadRegistration.register()
        AIAssistantFeaturePreloadRegistration.register()
        DocumentsFeaturePreloadRegistration.register()
        SettingsFeaturePreloadRegistration.register()
        ProfileFeaturePreloadRegistration.register()

        #if DEBUG
        registerFeaturePreload(
            FeaturePreloadDescriptor(
                id: "debug",
                title: "Debug surfaces",
                criticality: .bestEffort,
                timeoutSeconds: 0.3,
                retryLimit: 0,
                run: { _, onProgress, _ in
                    onProgress(1)
                }
            )
        )
        #endif
    }

    private func waitForStoreLoaded(_ collegePersistence: CollegePersistence) async {
        var pulse: Double = 0
        while !collegePersistence.isStoreLoaded {
            pulse += 0.08
            let softProgress = min(0.92, 0.08 + pulse.truncatingRemainder(dividingBy: 0.84))
            setStepProgress(.storeReady, progress: softProgress)
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        setStepProgress(.storeReady, progress: 1)
    }

    private func runRetriableStep(
        id: StepID,
        title: String,
        retriesUntilSuccess: Bool,
        operation: @escaping () async throws -> Void
    ) async {
        var attempt = 0
        lastErrorText = nil

        activeStepID = id
        currentStepNumber = stepNumber(for: id)
        currentStepProgress = stepProgress[id] ?? 0
        currentStepDetailText = "Preparing..."

        while !Task.isCancelled {
            currentStepTitle = title
            retryAttempt = attempt
            statusText = attempt == 0 ? "Running..." : "Retry attempt \(attempt)"

            do {
                try await LoadOperationTrace.withSpan(
                    name: "launch.\(id.traceName)",
                    category: .launch,
                    executionContext: .mainThread,
                    metadata: ["step_title": title]
                ) {
                    try await operation()
                }
                setStepProgress(id, progress: 1)
                retryAttempt = 0
                lastErrorText = nil
                if activeStepID == id {
                    currentStepProgress = 1
                    currentStepDetailText = "Done"
                }
                return
            } catch {
                lastErrorText = cleanedErrorMessage(error)
                if activeStepID == id {
                    currentStepDetailText = "Last failure: \(lastErrorText ?? "Unknown")"
                }

                if !retriesUntilSuccess {
                    statusText = "Skipped after error"
                    setStepProgress(id, progress: 1)
                    retryAttempt = 0
                    if activeStepID == id {
                        currentStepProgress = 1
                        currentStepDetailText = "Skipped"
                    }
                    return
                }

                attempt += 1
                retryAttempt = attempt
                let delaySeconds = min(10, max(1, attempt))
                statusText = "Retrying in \(delaySeconds)s..."
                if activeStepID == id {
                    currentStepDetailText = "Waiting before retry..."
                }
                try? await Task.sleep(nanoseconds: UInt64(delaySeconds) * 1_000_000_000)
            }
        }
    }

    private func cleanedErrorMessage(_ error: Error) -> String {
        let text = (error as NSError).localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "Unknown preload error" }
        return text
    }

    private func setStepProgress(_ id: StepID, progress: Double) {
        let clamped = min(1, max(0, progress))
        stepProgress[id] = clamped
        if activeStepID == id {
            currentStepProgress = clamped
        }
        recalculateOverallProgress()
    }

    private func setStepDetail(_ id: StepID, detail: String) {
        guard activeStepID == id else { return }
        let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        currentStepDetailText = trimmed.isEmpty ? "Working..." : trimmed
    }

    private func stepNumber(for id: StepID) -> Int {
        guard let index = StepID.allCases.firstIndex(of: id) else { return 0 }
        return index + 1
    }

    private func recalculateOverallProgress() {
        let totalWeight = stepWeights.values.reduce(0, +)
        guard totalWeight > 0 else {
            overallProgress = 0
            etaText = nil
            return
        }

        let weightedProgress = StepID.allCases.reduce(0.0) { partial, step in
            let weight = stepWeights[step] ?? 0
            let progress = stepProgress[step] ?? 0
            return partial + (weight * progress)
        }

        overallProgress = min(1, max(0, weightedProgress / totalWeight))
        updateETA()
    }

    private func updateETA() {
        let progress = overallProgress

        guard isRunning, !isCompleted, progress > 0.01, progress < 1 else {
            etaText = nil
            return
        }

        let now = Date()
        progressSamples.append((time: now, progress: progress))

        let maxAge: TimeInterval = 12
        progressSamples = progressSamples.filter { now.timeIntervalSince($0.time) <= maxAge }

        guard let first = progressSamples.first, let last = progressSamples.last else {
            etaText = nil
            return
        }

        let dt = last.time.timeIntervalSince(first.time)
        let dp = last.progress - first.progress
        guard dt > 0.6, dp > 0.001 else {
            etaText = "Estimating time remaining..."
            return
        }

        let velocity = dp / dt
        let remaining = (1 - progress) / velocity
        guard remaining.isFinite, remaining > 0 else {
            etaText = nil
            return
        }

        let seconds = Int(remaining.rounded())
        if seconds < 60 {
            etaText = "About \(seconds)s remaining"
            return
        }

        let minutes = Int((Double(seconds) / 60.0).rounded())
        etaText = "About \(minutes)m remaining"
    }
}

private extension LaunchPreloadCoordinator.StepID {
    var traceName: String {
        switch self {
        case .storeReady: return "storeReady"
        case .coreSnapshots: return "coreSnapshots"
        case .calendarWarmup: return "calendarWarmup"
        case .lmsWarmup: return "lmsWarmup"
        case .integrationsWarmup: return "integrationsWarmup"
        case .featureWarmup: return "featureWarmup"
        }
    }
}
