// CrashReportStore.swift
// Feature: Debug
// Purpose: Debug module — CrashReport.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import AppKit

struct CrashReport: Codable {
    enum Kind: String, Codable {
        case uncaughtException
        case abruptTermination
    }

    let id: String
    let createdAtISO8601: String
    let kind: Kind
    let summary: String
    let reason: String?
    let callStackSymbols: [String]
    let thread: String
    let appVersion: String
    let appBuild: String
    let osVersion: String
    let likelySource: String?
    let likelySourceReason: String?
    let likelySourceConfidence: Double?
}

enum CrashReportStore {
    private static let queue = DispatchQueue(label: "CrashReportStore.queue")
    private static let pendingCrashPathKey = "College.crash.pendingReportPath"
    private static let latestCrashPathKey = "College.crash.latestReportPath"
    private static let lastSeenSignalCrashMtimeKey = "College.crash.lastSeenSignalCrashMtime"

    static func installSignalCrashCaptureIfNeeded() {
        guard let signalURL = signalCrashReportURL() else { return }
        CrashSignalHandler.installIfNeeded(logPath: signalURL.path)
    }

    static func recordUncaughtException(name: String, reason: String, callStackSymbols: [String]) {
        let likely = deriveLikelySource(callStackSymbols: callStackSymbols)
        let report = CrashReport(
            id: UUID().uuidString,
            createdAtISO8601: iso8601String(Date()),
            kind: .uncaughtException,
            summary: "Uncaught NSException: \(name)",
            reason: reason,
            callStackSymbols: callStackSymbols,
            thread: Thread.isMainThread ? "main" : "background",
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            appBuild: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            likelySource: likely.source,
            likelySourceReason: likely.reason,
            likelySourceConfidence: likely.confidence
        )

        persist(report, synchronous: true)
        DiagnosticsEvent.emit(
            subsystem: .crash,
            severity: .critical,
            code: "CRASH_DETECTED",
            message: report.summary
        )
    }

    static func recordAbruptTerminationNoteIfNeeded() {
        queue.sync {
            let defaults = UserDefaults.standard
            guard defaults.string(forKey: pendingCrashPathKey) == nil else { return }

            let report = CrashReport(
                id: UUID().uuidString,
                createdAtISO8601: iso8601String(Date()),
                kind: .abruptTermination,
                summary: "Previous session ended unexpectedly",
                reason: "No uncaught exception report was captured. The process likely terminated abruptly (force quit, signal, or shutdown).",
                callStackSymbols: [],
                thread: "unknown",
                appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
                appBuild: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
                osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
                likelySource: nil,
                likelySourceReason: nil,
                likelySourceConfidence: nil
            )

            persist(report, synchronous: false)
        }
    }

    static func consumePendingCrashReportURL() -> URL? {
        let defaults = UserDefaults.standard
        guard let path = defaults.string(forKey: pendingCrashPathKey), !path.isEmpty else { return nil }
        defaults.removeObject(forKey: pendingCrashPathKey)

        let url = URL(fileURLWithPath: path)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static func latestCrashReportURL() -> URL? {
        let defaults = UserDefaults.standard
        guard let path = defaults.string(forKey: latestCrashPathKey), !path.isEmpty else { return nil }
        let url = URL(fileURLWithPath: path)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static func consumePendingSignalCrashReportURL() -> URL? {
        guard let url = signalCrashReportURL() else { return nil }
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return nil }

        let mtime = ((try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)?.timeIntervalSince1970) ?? 0
        let defaults = UserDefaults.standard
        let lastSeenMtime = defaults.double(forKey: lastSeenSignalCrashMtimeKey)
        guard mtime > 0, mtime > lastSeenMtime else { return nil }

        defaults.set(mtime, forKey: lastSeenSignalCrashMtimeKey)
        return url
    }

    static func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    static func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    static func copyPathToPasteboard(_ url: URL) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.path, forType: .string)
    }

    private static func persist(_ report: CrashReport, synchronous: Bool) {
        let write: @Sendable () -> Void = {
            guard let dir = reportsDirectoryURL() else { return }
            let fm = FileManager.default
            if !fm.fileExists(atPath: dir.path) {
                try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            }

            let safeTimestamp = report.createdAtISO8601.replacingOccurrences(of: ":", with: "-")
            let fileName = "crash_\(safeTimestamp)_\(report.id).json"
            let url = dir.appendingPathComponent(fileName)

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            guard let data = try? encoder.encode(report) else { return }

            do {
                try data.write(to: url, options: .atomic)
                let defaults = UserDefaults.standard
                defaults.set(url.path, forKey: pendingCrashPathKey)
                defaults.set(url.path, forKey: latestCrashPathKey)
            } catch {
                // Last-chance diagnostics should never crash the host app.
            }
        }

        if synchronous {
            queue.sync(execute: write)
        } else {
            queue.async(execute: write)
        }
    }

    private static func reportsDirectoryURL() -> URL? {
        let fm = FileManager.default
        guard let appSupport = try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else {
            return nil
        }

        let bundleID = Bundle.main.bundleIdentifier ?? "College"
        return appSupport
            .appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("CrashReports", isDirectory: true)
    }

    private static func signalCrashReportURL() -> URL? {
        reportsDirectoryURL()?.appendingPathComponent("signal_last_crash.txt")
    }

    private static func deriveLikelySource(callStackSymbols: [String]) -> (source: String?, reason: String?, confidence: Double?) {
        if let appFrame = callStackSymbols.first(where: { $0.contains("College`") || $0.contains("/College/") }) {
            return (
                source: appFrame,
                reason: "First in-app frame from the captured call stack.",
                confidence: 0.9
            )
        }

        if let top = callStackSymbols.first {
            return (
                source: top,
                reason: "Top captured frame (no explicit in-app frame found).",
                confidence: 0.45
            )
        }

        return (nil, nil, nil)
    }

    private static func iso8601String(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        return formatter.string(from: date)
    }
}
