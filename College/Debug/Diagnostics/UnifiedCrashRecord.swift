// UnifiedCrashRecord.swift
// Feature: Debug
// Purpose: Merge immediate local crash markers with later MetricKit diagnostics.

import Foundation

struct UnifiedCrashRecord: Sendable, Identifiable, Equatable {
    let id: String
    let sessionID: String
    let timestamp: Date
    let summary: String
    let localReportURL: URL?
    let signalReportURL: URL?
    let metricKitSummary: String?
    let hasMetricKitEnrichment: Bool
}

enum UnifiedCrashRecordBuilder {
    static func allRecords() async -> [UnifiedCrashRecord] {
        var records: [UnifiedCrashRecord] = []
        let localURLs = CrashReportStore.allReportURLs()
        let metricEvents = await DiagnosticsEventStore.shared.fetchRecent(
            limit: 100,
            subsystem: .metrickit
        ).filter { $0.code == "METRICKIT_CRASH" || $0.code == "METRICKIT_HANG" }

        for url in localURLs {
            let report = decodeReport(url)
            let sessionID = report?.id ?? url.lastPathComponent
            let metric = metricEvents.first { $0.sessionID == sessionID || $0.message.contains(url.lastPathComponent) }
            records.append(UnifiedCrashRecord(
                id: url.lastPathComponent,
                sessionID: sessionID,
                timestamp: reportDate(report, url: url),
                summary: report?.summary ?? url.lastPathComponent,
                localReportURL: url,
                signalReportURL: nil,
                metricKitSummary: metric.map { DiagnosticsPlainLanguage.summary(for: $0) },
                hasMetricKitEnrichment: metric != nil
            ))
        }

        if let signal = DiagnosticsArtifacts.crashReportsDirectory()?.appendingPathComponent("signal_last_crash.txt"),
           FileManager.default.fileExists(atPath: signal.path) {
            records.append(UnifiedCrashRecord(
                id: "signal_last_crash",
                sessionID: DiagnosticsSession.sessionID,
                timestamp: (try? signal.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date(),
                summary: "Fatal signal captured on last crash.",
                localReportURL: nil,
                signalReportURL: signal,
                metricKitSummary: nil,
                hasMetricKitEnrichment: false
            ))
        }

        return records.sorted { $0.timestamp > $1.timestamp }
    }

    static func likelySource(for report: CrashReport, hasMetricKit: Bool) -> String? {
        if hasMetricKit { return nil }
        return report.likelySource
    }

    private static func decodeReport(_ url: URL) -> CrashReport? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(CrashReport.self, from: data)
    }

    private static func reportDate(_ report: CrashReport?, url: URL) -> Date {
        if let iso = report?.createdAtISO8601,
           let date = ISO8601DateFormatter().date(from: iso) {
            return date
        }
        return (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
    }
}
