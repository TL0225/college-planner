// BackgroundServiceRegistry.swift
// Feature: Core/Platform
// Purpose: Central orchestrator for background service lifecycle.

import Foundation

@MainActor
final class BackgroundServiceRegistry {
    static let shared = BackgroundServiceRegistry()

    private var descriptors: [BackgroundServiceDescriptor] = []
    private var startedIDs: Set<String> = []
    private var pausedIDs: Set<String> = []
    private var sceneStartedPages: Set<AppPage> = []

    private init() {
        descriptors = BackgroundServiceManifest.allDescriptors()
    }

    static var allIDs: [String] {
        BackgroundServiceManifest.allDescriptors().map(\.id)
    }

    func descriptor(id: String) -> BackgroundServiceDescriptor? {
        descriptors.first { $0.id == id }
    }

    func bootstrap(phase: BackgroundServiceBootstrapPhase) async {
        let candidates = descriptors
            .filter { $0.activation.matches(bootstrap: phase, activePage: nil) }
            .sorted { $0.sortOrder < $1.sortOrder }

        for descriptor in candidates {
            await startIfNeeded(descriptor, respectThrottle: true)
        }
    }

    func sceneActivated(_ page: AppPage) async {
        guard sceneStartedPages.insert(page).inserted else { return }
        let candidates = descriptors
            .filter { $0.activation.matchesScene(page) }
            .sorted { $0.sortOrder < $1.sortOrder }
        for descriptor in candidates {
            await startIfNeeded(descriptor, respectThrottle: true)
        }
    }

    func isSceneActive(_ page: AppPage) -> Bool {
        sceneStartedPages.contains(page)
    }

    func registerOnDemand(id: String) async {
        await runOnDemand(id: id) { }
    }

    func runOnDemand(
        id: String,
        activityID: String? = nil,
        title: String? = nil,
        operation: @escaping @MainActor () async throws -> Void
    ) async {
        guard validateOnDemandID(id) else { return }
        guard let descriptor = descriptor(id: id) else { return }
        let resolvedTitle = title ?? descriptor.displayName
        let resolvedActivityID = activityID ?? descriptor.activityDomain.map { _ in id }
        RuntimeTelemetryMonitor.shared.markServiceState(id, state: "running")
        if let resolvedActivityID, let domain = descriptor.activityDomain {
            BackgroundServiceExecutor.reportRunning(
                id: resolvedActivityID,
                domain: domain,
                title: resolvedTitle,
                indeterminate: true
            )
        }
        do {
            try await operation()
            RuntimeTelemetryMonitor.shared.markServiceState(id, state: "completed")
            if let resolvedActivityID {
                BackgroundServiceExecutor.reportFinish(id: resolvedActivityID, succeeded: true, summary: "Done")
            }
        } catch is CancellationError {
            RuntimeTelemetryMonitor.shared.markServiceState(id, state: "cancelled")
        } catch {
            RuntimeTelemetryMonitor.shared.markServiceState(id, state: "failed")
            DebugLogger.shared.log(
                "On-demand service \(id) failed: \(error.localizedDescription)",
                category: .system,
                level: .error
            )
            if let resolvedActivityID {
                BackgroundActivityReporter.finish(
                    id: resolvedActivityID,
                    succeeded: false,
                    summary: error.localizedDescription
                )
            }
        }
    }

    func runOnDemandThrowing<T: Sendable>(
        id: String,
        title: String? = nil,
        operation: @escaping @MainActor () async throws -> T
    ) async throws -> T {
        guard validateOnDemandID(id) else {
            return try await operation()
        }
        guard let descriptor = descriptor(id: id) else {
            return try await operation()
        }
        let resolvedTitle = title ?? descriptor.displayName
        let activityID = descriptor.activityDomain.map { _ in id }
        RuntimeTelemetryMonitor.shared.markServiceState(id, state: "running")
        if let activityID, let domain = descriptor.activityDomain {
            BackgroundServiceExecutor.reportRunning(
                id: activityID,
                domain: domain,
                title: resolvedTitle,
                indeterminate: true
            )
        }
        do {
            let value = try await operation()
            RuntimeTelemetryMonitor.shared.markServiceState(id, state: "completed")
            if let activityID {
                BackgroundServiceExecutor.reportFinish(id: activityID, succeeded: true, summary: "Done")
            }
            return value
        } catch is CancellationError {
            RuntimeTelemetryMonitor.shared.markServiceState(id, state: "cancelled")
            throw CancellationError()
        } catch {
            RuntimeTelemetryMonitor.shared.markServiceState(id, state: "failed")
            DebugLogger.shared.log(
                "On-demand service \(id) failed: \(error.localizedDescription)",
                category: .system,
                level: .error
            )
            if let activityID {
                BackgroundServiceExecutor.reportFinish(
                    id: activityID,
                    succeeded: false,
                    summary: error.localizedDescription
                )
            }
            throw error
        }
    }

    func runOnDemandReturning<T>(
        id: String,
        title: String? = nil,
        operation: @escaping @MainActor () async -> T
    ) async -> T {
        guard validateOnDemandID(id) else {
            return await operation()
        }
        RuntimeTelemetryMonitor.shared.markServiceState(id, state: "running")
        let value = await operation()
        RuntimeTelemetryMonitor.shared.markServiceState(id, state: "completed")
        return value
    }

    private func validateOnDemandID(_ id: String) -> Bool {
        #if DEBUG
        guard descriptors.contains(where: { $0.id == id }) else {
            assertionFailure("Unknown on-demand service id: \(id)")
            return false
        }
        #endif
        return descriptor(id: id) != nil
    }

    func pauseAll(matching policy: BackgroundServiceThrottlePolicy = .pauseWhenInactive) async {
        for descriptor in descriptors where descriptor.throttle == policy {
            guard startedIDs.contains(descriptor.id), !pausedIDs.contains(descriptor.id) else { continue }
            pausedIDs.insert(descriptor.id)
            RuntimeTelemetryMonitor.shared.markServiceState(descriptor.id, state: "paused")
            if let pause = descriptor.pause {
                await pause()
            } else {
                await descriptor.stop()
            }
        }
    }

    func resumeAll() async {
        let toResume = pausedIDs
        pausedIDs.removeAll()
        for id in toResume {
            guard let descriptor = descriptor(id: id) else { continue }
            RuntimeTelemetryMonitor.shared.markServiceState(id, state: "resuming")
            if let resume = descriptor.resume {
                await resume()
            } else {
                await descriptor.start()
            }
        }
    }

    func stopAll() async {
        for id in startedIDs.sorted() {
            guard let descriptor = descriptor(id: id) else { continue }
            await descriptor.stop()
            RuntimeTelemetryMonitor.shared.markServiceState(id, state: "stopped")
        }
        startedIDs.removeAll()
        pausedIDs.removeAll()
        sceneStartedPages.removeAll()
    }

    #if DEBUG
    /// Replaces manifest descriptors for unit tests. Resets started state.
    func _testingReplaceDescriptors(_ descriptors: [BackgroundServiceDescriptor]) {
        self.descriptors = descriptors
        startedIDs.removeAll()
        pausedIDs.removeAll()
        sceneStartedPages.removeAll()
        testingStartFailureIDs.removeAll()
    }

    /// Simulates a start failure for the given descriptor ids (failure isolation tests).
    func _testingSetStartFailure(ids: Set<String>) {
        testingStartFailureIDs = ids
    }

    var _testingStartedIDs: Set<String> { startedIDs }

    private var testingStartFailureIDs: Set<String> = []
    #endif

    // MARK: - Private

    private func startIfNeeded(_ descriptor: BackgroundServiceDescriptor, respectThrottle: Bool) async {
        guard !startedIDs.contains(descriptor.id) else { return }
        if respectThrottle,
           descriptor.throttle == .deferUntilActive,
           AppActivityCoordinator.shared.isResourceThrottled {
            return
        }
        if respectThrottle,
           descriptor.throttle == .pauseWhenInactive,
           AppActivityCoordinator.shared.isResourceThrottled {
            return
        }

        await startDescriptor(descriptor)
    }

    private func startDescriptor(_ descriptor: BackgroundServiceDescriptor) async {
        #if DEBUG
        if testingStartFailureIDs.contains(descriptor.id) {
            RuntimeTelemetryMonitor.shared.markServiceState(descriptor.id, state: "failed")
            DebugLogger.shared.log(
                "Failed to start background service \(descriptor.id): simulated test failure",
                category: .system,
                level: .error
            )
            return
        }
        #endif
        RuntimeTelemetryMonitor.shared.markServiceState(descriptor.id, state: "starting")
        do {
            if let lane = descriptor.resourceLane {
                try await LaunchStartupBudget.shared.run(lane: lane) {
                    await descriptor.start()
                }
            } else {
                await descriptor.start()
            }
            startedIDs.insert(descriptor.id)
            RuntimeTelemetryMonitor.shared.markServiceState(descriptor.id, state: "running")
        } catch {
            DebugLogger.shared.log(
                "Failed to start background service \(descriptor.id): \(error.localizedDescription)",
                category: .system,
                level: .error
            )
            RuntimeTelemetryMonitor.shared.markServiceState(descriptor.id, state: "failed")
        }
    }
}
