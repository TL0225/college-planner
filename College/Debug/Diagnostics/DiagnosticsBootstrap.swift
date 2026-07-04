// DiagnosticsBootstrap.swift
// Feature: Debug
// Purpose: Deferred initialization of diagnostics subsystems after launch.

import Foundation

enum DiagnosticsBootstrap {
    private static let startedLock = NSLock()
    nonisolated(unsafe) private static var started = false

    static func startDeferredServices() {
        startedLock.lock()
        guard !started else {
            startedLock.unlock()
            return
        }
        started = true
        startedLock.unlock()

        Task.detached(priority: .utility) {
            await DiagnosticsEventStore.shared.openIfNeeded()
            await DiagnosticsStorageMigration.runIfNeeded()
            MetricKitDiagnosticsCollector.shared.registerIfNeeded()
            DiagnosticsEvent.emit(
                subsystem: .app,
                severity: .info,
                code: "DIAGNOSTICS_READY",
                message: "Diagnostics platform initialized."
            )
        }
    }
}
