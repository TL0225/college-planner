// CatalogHostRequestScheduler.swift
// Feature: Catalog
// Purpose: Catalog module — CatalogHostRequestScheduler.
// Data: CollegePersistence / repositories when applicable.

import Foundation

/// Per-host serialized spacing so concurrent tasks cannot stampede the origin before `Task.sleep` yields.
actor CatalogHostRequestScheduler {
    static let shared = CatalogHostRequestScheduler()

    private var nextAllowedAt: [String: Date] = [:]

    /// Reserves the next slot for `host`, waits until it is available, then advances the deadline by `minSpacing`.
    func acquire(host: String, minSpacing: TimeInterval) async {
        let key = host.lowercased()
        guard !key.isEmpty else { return }

        let now = Date()
        let slotStart = max(nextAllowedAt[key] ?? now, now)
        let wait = slotStart.timeIntervalSince(now)
        nextAllowedAt[key] = slotStart.addingTimeInterval(max(0, minSpacing))

        guard wait > 0.04 else { return }
        let jitter = Double.random(in: 0...0.12)
        try? await Task.sleep(nanoseconds: UInt64((wait + jitter) * 1_000_000_000))
    }
}
