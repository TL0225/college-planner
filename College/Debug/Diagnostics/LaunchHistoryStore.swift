// LaunchHistoryStore.swift
// Feature: Debug
// Purpose: Ring buffer of recent launch performance records.

import Foundation

struct LaunchHistoryEntry: Codable, Sendable, Identifiable, Equatable {
    var id: String { startedAtISO8601 }
    let startedAtISO8601: String
    let launchDurationMs: Int
    let footprintAtLaunchMB: Double
    let startupFailure: String?
}

enum LaunchHistoryStore {
    private static let maxEntries = 20

    static func recordLaunch(
        durationMs: Int,
        footprintMB: Double,
        startupFailure: String? = nil,
        startedAt: Date = Date()
    ) {
        var entries = loadAll()
        let formatter = ISO8601DateFormatter()
        let entry = LaunchHistoryEntry(
            startedAtISO8601: formatter.string(from: startedAt),
            launchDurationMs: durationMs,
            footprintAtLaunchMB: footprintMB,
            startupFailure: startupFailure
        )
        entries.insert(entry, at: 0)
        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }
        persist(entries)
        DiagnosticsEvent.emit(
            subsystem: .launch,
            severity: startupFailure == nil ? .info : .error,
            code: startupFailure == nil ? "LAUNCH_COMPLETE" : "LAUNCH_FAILED",
            message: startupFailure ?? "Launch completed in \(durationMs) ms."
        )
    }

    static func loadAll() -> [LaunchHistoryEntry] {
        guard let url = DiagnosticsArtifacts.launchHistoryURL(),
              let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([LaunchHistoryEntry].self, from: data)) ?? []
    }

    static func latest() -> LaunchHistoryEntry? {
        loadAll().first
    }

    private static func persist(_ entries: [LaunchHistoryEntry]) {
        guard let url = DiagnosticsArtifacts.launchHistoryURL(create: true) else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(entries) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
