// SupportSnapshotGenerator.swift
// Feature: Debug
// Purpose: support-summary.json — first file in every diagnostic export.

import Foundation

struct SupportSnapshot: Codable, Sendable, Equatable {
    let health: String
    let crashes30d: Int
    let modelLoaded: Bool
    let catalogHealthy: Bool
    let launchStatus: String
    let memoryStatus: String
    let topWarnings: [String]
    let exportNote: String?
}

enum SupportSnapshotGenerator {
    static func generate(exportNote: String? = nil) async -> SupportSnapshot {
        let report = await DiagnosticsHealthReportBuilder.generate()
        let thirtyDaysAgo = Date().addingTimeInterval(-30 * 86_400)
        let crashCount = await DiagnosticsEventStore.shared.countEvents(since: thirtyDaysAgo, severity: .critical)
            + CrashReportStore.allReportURLs(since: thirtyDaysAgo).count

        let catalogHealthy = report.checks.first { $0.id == "catalog" }?.status == .good
        let modelLoaded = report.checks.first { $0.id == "model" }?.status == .good

        let launchStatus = LaunchHistoryStore.latest()?.startupFailure == nil ? "ok" : "failed"
        let memoryStatus = report.checks.first { $0.id == "memory" }?.status == .good ? "ok" : "pressure"

        return SupportSnapshot(
            health: report.band.rawValue,
            crashes30d: crashCount,
            modelLoaded: modelLoaded,
            catalogHealthy: catalogHealthy,
            launchStatus: launchStatus,
            memoryStatus: memoryStatus,
            topWarnings: report.warnings.map(\.message),
            exportNote: exportNote
        )
    }

    static func writeJSON(to url: URL, exportNote: String? = nil) async throws {
        let snapshot = await generate(exportNote: exportNote)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot)
        try data.write(to: url, options: .atomic)
    }
}
