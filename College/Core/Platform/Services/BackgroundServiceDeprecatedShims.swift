// BackgroundServiceDeprecatedShims.swift
// Feature: Core/Platform
// Purpose: Compile-time friction for removed ad-hoc background lifecycle patterns.

import Foundation

/// Deprecated entry points retained only to surface compile-time guidance.
/// Do not call these from new code — register services in `BackgroundServiceManifest`.
enum BackgroundServiceDeprecatedShims {
    @available(
        *,
        deprecated,
        message: "Register the service in BackgroundServiceManifest and start it via BackgroundServiceRegistry."
    )
    static func startTrackedServiceTask(
        name: String,
        priority: TaskPriority = .utility,
        operation: @escaping @Sendable () async -> Void
    ) {
        Task(priority: priority) {
            await operation()
        }
    }

    @available(
        *,
        deprecated,
        message: "Use BackgroundServiceScheduler instead of NSBackgroundActivityScheduler directly."
    )
    static func makeBackgroundActivityScheduler(identifier: String) -> NSBackgroundActivityScheduler {
        NSBackgroundActivityScheduler(identifier: identifier)
    }
}
