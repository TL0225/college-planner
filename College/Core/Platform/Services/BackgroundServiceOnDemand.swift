// BackgroundServiceOnDemand.swift
// Feature: Core/Platform
// Purpose: Typed entry point for Tier 2 on-demand work units (manifest-gated).

import Foundation

/// Routes user-initiated / coordinator-triggered work through `BackgroundServiceRegistry`.
enum BackgroundServiceOnDemand {
    /// Runs a non-throwing on-demand unit on the main actor.
    @MainActor
    static func run(
        id: String,
        title: String? = nil,
        operation: @escaping @MainActor () async -> Void
    ) async {
        await BackgroundServiceRegistry.shared.runOnDemand(id: id, title: title) {
            await operation()
        }
    }

    /// Runs a throwing on-demand unit on the main actor; rethrows after telemetry + activity reporting.
    @MainActor
    static func runThrowing<T: Sendable>(
        id: String,
        title: String? = nil,
        operation: @escaping @MainActor () async throws -> T
    ) async throws -> T {
        try await BackgroundServiceRegistry.shared.runOnDemandThrowing(id: id, title: title, operation: operation)
    }

    /// Runs an on-demand unit and returns its value (telemetry only; errors propagate from `operation` if throwing).
    @MainActor
    static func runReturning<T>(
        id: String,
        title: String? = nil,
        operation: @escaping @MainActor () async -> T
    ) async -> T {
        await BackgroundServiceRegistry.shared.runOnDemandReturning(id: id, title: title, operation: operation)
    }

    /// Runs CPU/IO-heavy on-demand work off the main actor (telemetry + activity on MainActor).
    static func runOffMain(
        id: String,
        title: String? = nil,
        operation: @escaping @Sendable () async throws -> Void
    ) async {
        await BackgroundServiceExecutor.runWorkUnit(
            serviceID: id,
            title: title,
            operation: operation
        )
    }
}
