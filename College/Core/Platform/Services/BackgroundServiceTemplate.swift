// BackgroundServiceTemplate.swift
// Feature: Core/Platform
// Purpose: Canonical scaffold for new background/sync services. Copy and adapt — do not ship as-is.

import Foundation
import SwiftData

// MARK: - 1. Fetcher actor (network + parse → Sendable snapshot)

actor ExampleBackgroundFetcher {
    struct Snapshot: Sendable {
        let payload: String
    }

    func fetch() async throws -> Snapshot {
        try await BackgroundServiceExecutor.fetchOffMain {
            // URLSession, HTML/PDF parse, etc. — never on MainActor.
            Snapshot(payload: "example")
        }
    }
}

// MARK: - 2. @MainActor shell (scheduler + progress only)

@MainActor
final class ExampleBackgroundService {
    static let shared = ExampleBackgroundService()

    private let scheduler = BackgroundServiceScheduler(identifier: "com.college.example.refresh")
    private let fetcher = ExampleBackgroundFetcher()

    private init() {}

    func start() {
        scheduler.configure(repeats: true, interval: 3600, tolerance: 600)
        scheduler.start { [weak self] completion in
            await self?.runRefreshTick()
            completion(.finished)
        }
    }

    func stop() {
        scheduler.invalidate()
    }

    private func runRefreshTick() async {
        await BackgroundServiceExecutor.runWorkUnit(
            serviceID: "example_background",
            activityID: "example_background",
            domain: .catalog,
            title: "Example Refresh",
            operation: { [fetcher] in
                let snapshot = try await fetcher.fetch()
                _ = snapshot
            },
            onFailure: { error in
                BackgroundActivityReporter.finish(
                    id: "example_background",
                    succeeded: false,
                    summary: error.localizedDescription
                )
            }
        )
    }
}

// MARK: - 3. Manifest registration (BackgroundServiceManifest.swift)

/*
 BackgroundServiceDescriptor(
     id: "example_background",
     displayName: "Example Background",
     activityDomain: .catalog,
     activation: .atMainUIReady,
     throttle: .pauseWhenInactive,
     sortOrder: 900,
     start: { ExampleBackgroundService.shared.start() },
     stop: { ExampleBackgroundService.shared.stop() }
 )
 */

// MARK: - 4. Persistence (when needed)

/*
 try await BackgroundServiceExecutor.persistOffMain(container: container) { ctx in
     // SwiftData writes on isolated ModelContext
 }
 */
