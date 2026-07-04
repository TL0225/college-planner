// DiagnosticsExportPolicy.swift
// Feature: Debug
// Purpose: Scoping and size caps for diagnostic bundle exports.

import Foundation

enum DiagnosticsExportLevel: String, CaseIterable, Identifiable, Sendable {
    case basic
    case full

    var id: String { rawValue }

    var title: String {
        switch self {
        case .basic: return "Basic"
        case .full: return "Full"
        }
    }

    var subtitle: String {
        switch self {
        case .basic: return "Logs, crashes, and summary (~5–20 MB)"
        case .full: return "Adds catalog reports and diagnostic tables (~20–100 MB)"
        }
    }
}

struct DiagnosticsExportPolicy: Sendable {
    let level: DiagnosticsExportLevel
    let logMaxAge: TimeInterval
    let hardSizeCapBytes: Int64
    let includeEventStore: Bool
    let includeCrashReports: Bool
    let includeMetricKitPayloads: Bool
    let includeLaunchHistory: Bool
    let includeCatalogReports: Bool
    let includeSQLiteDiagnosticTables: Bool
    let excludeVectorIndexes: Bool

    static func policy(for level: DiagnosticsExportLevel) -> DiagnosticsExportPolicy {
        switch level {
        case .basic:
            return DiagnosticsExportPolicy(
                level: .basic,
                logMaxAge: 7 * 86_400,
                hardSizeCapBytes: 20 * 1024 * 1024,
                includeEventStore: true,
                includeCrashReports: true,
                includeMetricKitPayloads: true,
                includeLaunchHistory: true,
                includeCatalogReports: false,
                includeSQLiteDiagnosticTables: false,
                excludeVectorIndexes: true
            )
        case .full:
            return DiagnosticsExportPolicy(
                level: .full,
                logMaxAge: 7 * 86_400,
                hardSizeCapBytes: 100 * 1024 * 1024,
                includeEventStore: true,
                includeCrashReports: true,
                includeMetricKitPayloads: true,
                includeLaunchHistory: true,
                includeCatalogReports: true,
                includeSQLiteDiagnosticTables: true,
                excludeVectorIndexes: true
            )
        }
    }

    func resolvedURLs(truncationNote: inout String?) -> [URL] {
        var urls: [URL] = []
        let fm = FileManager.default
        var totalBytes: Int64 = 0

        func addURL(_ url: URL) {
            guard fm.fileExists(atPath: url.path) else { return }
            let size = fileSize(url)
            if totalBytes + size > hardSizeCapBytes {
                truncationNote = "Some older files were omitted to stay within the \(level.title) export size limit."
                return
            }
            totalBytes += size
            urls.append(url)
        }

        if includeEventStore, let url = DiagnosticsArtifacts.eventStoreURL() {
            addURL(url)
            addURL(url.appendingPathExtension("wal"))
            addURL(url.appendingPathExtension("shm"))
        }
        if includeLaunchHistory, let url = DiagnosticsArtifacts.launchHistoryURL() {
            addURL(url)
        }
        if includeCrashReports {
            for url in CrashReportStore.allReportURLs() { addURL(url) }
            if let signal = DiagnosticsArtifacts.crashReportsDirectory()?.appendingPathComponent("signal_last_crash.txt") {
                addURL(signal)
            }
        }
        if includeMetricKitPayloads, let dir = DiagnosticsArtifacts.metricKitPayloadsDirectory() {
            if let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
                for url in files { addURL(url) }
            }
        }
        if let logsDir = DiagnosticsArtifacts.logsDirectory(),
           let files = try? fm.contentsOfDirectory(at: logsDir, includingPropertiesForKeys: [.contentModificationDateKey]) {
            let cutoff = Date().addingTimeInterval(-logMaxAge)
            let sorted = files.sorted {
                let d0 = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let d1 = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return d0 > d1
            }
            for url in sorted {
                let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                guard mtime >= cutoff else { continue }
                addURL(url)
            }
        }
        if includeCatalogReports, let reportsDir = DiagnosticsArtifacts.migratedReportsDirectory(),
           let files = try? fm.contentsOfDirectory(at: reportsDir, includingPropertiesForKeys: nil) {
            for url in files.sorted(by: { $0.lastPathComponent > $1.lastPathComponent }).prefix(5) {
                addURL(url)
            }
        }
        if includeSQLiteDiagnosticTables, let collegeDir = DiagnosticsArtifacts.collegeDataDirectory(),
           let files = try? fm.contentsOfDirectory(at: collegeDir, includingPropertiesForKeys: nil) {
            for url in files where url.pathExtension == "sqlite" {
                if excludeVectorIndexes, url.lastPathComponent.contains("vector") { continue }
                addURL(url)
            }
        }

        return urls
    }

    private func fileSize(_ url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }
}
