// CatalogEmbedMemoryLifecycle.swift
// Feature: Catalog
// Purpose: Catalog module — CatalogEmbedMemoryLifecycle.
// Data: CollegePersistence / repositories when applicable.

import Foundation

/// Idle unload coordinator for MLX catalog embedder weights (mirrors ``LLMMemoryLifecycle``).
@MainActor
final class CatalogEmbedMemoryLifecycle {
    static let shared = CatalogEmbedMemoryLifecycle()

    static let idleTimeoutSecondsKey = "catalog.embed.idleTimeoutSeconds"

    private var idleTask: Task<Void, Never>?
    private(set) var lastIdleReleaseAt: Date?

    var idleTimeout: TimeInterval {
        let stored = UserDefaults.standard.double(forKey: Self.idleTimeoutSecondsKey)
        return stored > 0 ? stored : 120
    }

    func touch() {
        scheduleIdleRelease()
    }

    func cancelIdleRelease() {
        idleTask?.cancel()
        idleTask = nil
    }

    func releaseNow() {
        cancelIdleRelease()
        Task {
            await CatalogMLXEmbedService.shared.reset()
            lastIdleReleaseAt = Date()
        }
    }

    func scheduleIdleRelease() {
        cancelIdleRelease()
        let seconds = idleTimeout
        idleTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await CatalogMLXEmbedService.shared.reset()
            lastIdleReleaseAt = Date()
            DebugLogger.shared.log(
                "CatalogEmbedMemoryLifecycle: idle release after \(Int(seconds))s",
                category: .system,
                level: .info
            )
        }
    }
}
