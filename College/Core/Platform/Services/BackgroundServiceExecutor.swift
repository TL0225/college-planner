// BackgroundServiceExecutor.swift
// Feature: Core/Platform
// Purpose: Standard execution pipeline for off-main fetch, persist, and isolated work units.

import Foundation
import SwiftData

enum BackgroundServiceExecutor {
    /// Network + parse off the main actor; returns a `Sendable` snapshot.
    static func fetchOffMain<T: Sendable>(
        priority: TaskPriority = .utility,
        _ body: @Sendable @escaping () async throws -> T
    ) async throws -> T {
        try await Task.detached(priority: priority) {
            try await body()
        }.value
    }

    /// SwiftData writes on a detached task with an isolated `ModelContext`.
    static func persistOffMain<T: Sendable>(
        lane: LaunchStartupBudget.Lane = .database,
        container: ModelContainer,
        operationName: String = "persistOffMain",
        category: LoadOperationCategory = .general,
        _ body: @Sendable @escaping (ModelContext) async throws -> T
    ) async throws -> T {
        try await LoadOperationTrace.withSpan(
            name: operationName,
            category: category,
            metadata: ["lane": Self.laneLabel(lane)]
        ) {
            try await LaunchStartupBudget.shared.run(lane: lane) {
                try await Task.detached(priority: .utility) {
                    let ctx = BackgroundModelContextPolicy.makeReadContext(container: container)
                    return try await body(ctx)
                }.value
            }
        }
    }

    @MainActor
    static func reportRunning(
        id: String,
        domain: BackgroundActivityDomain,
        title: String,
        detail: String? = nil,
        fraction: Double? = nil,
        indeterminate: Bool = false
    ) {
        BackgroundActivityReporter.running(
            id: id,
            domain: domain,
            title: title,
            detail: detail,
            fraction: fraction,
            indeterminate: indeterminate
        )
    }

    @MainActor
    static func reportFinish(id: String, succeeded: Bool, summary: String) {
        BackgroundActivityReporter.finish(id: id, succeeded: succeeded, summary: summary)
    }

    /// Wraps a unit of work with telemetry, local failure containment, and optional cancellation checks.
    @MainActor
    static func runWorkUnit(
        serviceID: String,
        activityID: String? = nil,
        domain: BackgroundActivityDomain? = nil,
        priority: TaskPriority = .utility,
        title: String? = nil,
        checkCancellation: (() throws -> Void)? = nil,
        operation: @escaping @Sendable () async throws -> Void,
        onFailure: ((Error) -> Void)? = nil
    ) async {
        RuntimeTelemetryMonitor.shared.markServiceState(serviceID, state: "running")
        if let activityID, let domain, let title {
            reportRunning(id: activityID, domain: domain, title: title, indeterminate: true)
        }

        do {
            try checkCancellation?()
            try await LoadOperationTrace.withSpan(
                name: serviceID,
                category: .backgroundService,
                executionContext: .background,
                metadata: [
                    "domain": domain?.rawValue ?? "",
                    "activity_id": activityID ?? ""
                ]
            ) {
                try await Task.detached(priority: priority) {
                    try await operation()
                }.value
            }
            RuntimeTelemetryMonitor.shared.markServiceState(serviceID, state: "completed")
            if let activityID {
                reportFinish(id: activityID, succeeded: true, summary: "Done")
            }
        } catch is CancellationError {
            RuntimeTelemetryMonitor.shared.markServiceState(serviceID, state: "cancelled")
        } catch {
            RuntimeTelemetryMonitor.shared.markServiceState(serviceID, state: "failed")
            DebugLogger.shared.log(
                "Background service \(serviceID) failed: \(error.localizedDescription)",
                category: .system,
                level: .error
            )
            if let onFailure {
                onFailure(error)
            } else if let activityID {
                reportFinish(id: activityID, succeeded: false, summary: error.localizedDescription)
            }
        }
    }

    #if DEBUG
    static func assertNotOnMainActor(file: StaticString = #file, line: UInt = #line) {
        assert(!Thread.isMainThread, "Background work must not run on MainActor (\(file):\(line))")
    }
    #endif

    private static func laneLabel(_ lane: LaunchStartupBudget.Lane) -> String {
        switch lane {
        case .database: return "database"
        case .fileIO: return "fileIO"
        }
    }
}
