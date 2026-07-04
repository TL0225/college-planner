// SubsystemMemoryEstimator.swift
// Feature: Debug
// Purpose: Rough per-subsystem memory ownership estimates for support.

import Foundation

struct SubsystemMemoryEstimate: Sendable, Identifiable, Equatable {
    let id: String
    let title: String
    let estimatedMB: Double
    let detail: String
    /// Optional reassuring/contextual note shown beneath the row (e.g. expected ranges).
    var note: String? = nil
    /// Optional short status badge (e.g. "Not loaded") that echoes a health warning.
    var badge: String? = nil
}

enum SubsystemMemoryEstimator {
    nonisolated(unsafe) private static var cache: (estimates: [SubsystemMemoryEstimate], fetchedAt: Date)?
    private static let cacheTTL: TimeInterval = 15

    static func estimates(forceRefresh: Bool = false) -> [SubsystemMemoryEstimate] {
        let now = Date()
        if !forceRefresh, let cache, now.timeIntervalSince(cache.fetchedAt) < cacheTTL {
            return cache.estimates
        }
        let computed = computeEstimates()
        cache = (computed, now)
        return computed
    }

    static func totalEstimatedMB() -> Double {
        estimates().reduce(0) { $0 + $1.estimatedMB }
    }

    private static func computeEstimates() -> [SubsystemMemoryEstimate] {
        let footprint = PerformanceDiagnostics.footprintMemoryMB()
        var items: [SubsystemMemoryEstimate] = []

        let mlxMB = estimatedMLXMB()
        items.append(.init(
            id: "mlx",
            title: "MLX Models",
            estimatedMB: mlxMB,
            detail: "On-device model weights and GPU allocations.",
            badge: mlxMB <= 0 ? "Not loaded" : nil
        ))

        let catalogMB = directorySizeMB(DiagnosticsArtifacts.collegeDataDirectory())
        items.append(.init(
            id: "catalog",
            title: "Catalog Cache",
            estimatedMB: catalogMB,
            detail: "Catalog stores, indexes, and cached scrape data."
        ))

        let sqliteMB = sqliteCachesMB()
        items.append(.init(
            id: "sqlite",
            title: "SQLite Caches",
            estimatedMB: sqliteMB,
            detail: "Vector indexes and planner databases."
        ))

        let logsMB = directorySizeMB(DiagnosticsArtifacts.logsDirectory())
        items.append(.init(
            id: "logs",
            title: "Logs & Diagnostics",
            estimatedMB: logsMB,
            detail: "App logs, crash reports, and diagnostic artifacts."
        ))

        let accounted = items.reduce(0) { $0 + $1.estimatedMB }
        let other = max(0, footprint - accounted)
        items.append(.init(
            id: "other",
            title: "Other",
            estimatedMB: other,
            detail: "App runtime, UI, WebKit, and shared frameworks.",
            note: "This is expected for a running app — typical range is 800 MB–1.8 GB on Apple Silicon."
        ))

        return items.sorted { $0.estimatedMB > $1.estimatedMB }
    }

    private static func estimatedMLXMB() -> Double {
        let key = "assistant.mlx.peakMemoryMB"
        let stored = UserDefaults.standard.double(forKey: key)
        if stored > 0 { return stored }
        return 0
    }

    private static func sqliteCachesMB() -> Double {
        guard let collegeDir = DiagnosticsArtifacts.collegeDataDirectory() else { return 0 }
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: collegeDir, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        let sqliteFiles = files.filter { $0.pathExtension == "sqlite" || $0.lastPathComponent.contains("vector") }
        return sqliteFiles.reduce(0) { partial, url in
            partial + fileSizeMB(url)
        }
    }

    private static func directorySizeMB(_ url: URL?) -> Double {
        guard let url else { return 0 }
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            total += (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        }
        return Double(total) / 1_048_576.0
    }

    private static func fileSizeMB(_ url: URL) -> Double {
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return Double(bytes) / 1_048_576.0
    }

    /// Human-readable warnings for Assistant / Apply memory pressure (M30-067).
    static func subsystemWarnings() -> [String] {
        var warnings: [String] = []
        let footprint = PerformanceDiagnostics.footprintMemoryMB()
        let mlxMB = estimatedMLXMB()

        if mlxMB > 0, mlxMB > assistantMLXWarnMB() {
            warnings.append("Assistant model memory is elevated (\(Int(mlxMB.rounded())) MB).")
        }
        if footprint > assistantFootprintWarnMB() {
            warnings.append("App memory footprint is high (\(Int(footprint.rounded())) MB).")
        }
        return warnings
    }

    static func emitSubsystemWarningsIfNeeded() {
        for message in subsystemWarnings() {
            DiagnosticsEvent.emit(
                subsystem: .memory,
                severity: .warning,
                code: "memory.subsystem.elevated",
                message: message,
                category: "memory.budget"
            )
        }
    }

    private static func assistantMLXWarnMB() -> Double {
        #if DEBUG
        2_500
        #else
        1_800
        #endif
    }

    private static func assistantFootprintWarnMB() -> Double {
        #if DEBUG
        2_800
        #else
        2_000
        #endif
    }
}
