// DiagnosticsArtifacts.swift
// Feature: Debug
// Purpose: Single source of truth for diagnostic artifact paths and UserDefaults keys.

import Foundation

/// One discoverable diagnostic artifact (file, directory, or logical group).
struct DiagnosticsArtifact: Sendable, Equatable, Identifiable {
    let id: String
    let title: String
    let kind: Kind
    let url: URL?
    let userDefaultsKeys: [String]
    let userDefaultsKeyPrefixes: [String]

    enum Kind: String, Sendable {
        case file
        case directory
        case userDefaultsOnly
    }
}

/// Central registry of every on-disk path and diagnostic UserDefaults key.
enum DiagnosticsArtifacts {
    static var bundleID: String { Bundle.main.bundleIdentifier ?? "College" }

    static func applicationSupportBase(create: Bool = false) -> URL? {
        let fm = FileManager.default
        return try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: create
        )
    }

    static func bundleSupportDirectory(create: Bool = false) -> URL? {
        guard let base = applicationSupportBase(create: create) else { return nil }
        let dir = base.appendingPathComponent(bundleID, isDirectory: true)
        if create, !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    static func diagnosticsDirectory(create: Bool = false) -> URL? {
        guard let base = bundleSupportDirectory(create: create) else { return nil }
        let dir = base.appendingPathComponent("Diagnostics", isDirectory: true)
        if create, !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    static func eventStoreURL(create: Bool = false) -> URL? {
        diagnosticsDirectory(create: create)?.appendingPathComponent("events.sqlite")
    }

    static func launchHistoryURL(create: Bool = false) -> URL? {
        diagnosticsDirectory(create: create)?.appendingPathComponent("launch-history.json")
    }

    static func metricKitPayloadsDirectory(create: Bool = false) -> URL? {
        guard let base = diagnosticsDirectory(create: create) else { return nil }
        let dir = base.appendingPathComponent("MetricKit", isDirectory: true)
        if create, !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    static func migratedReportsDirectory(create: Bool = false) -> URL? {
        guard let base = diagnosticsDirectory(create: create) else { return nil }
        let dir = base.appendingPathComponent("Reports", isDirectory: true)
        if create, !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    static func logsDirectory() -> URL? {
        bundleSupportDirectory()?.appendingPathComponent("Logs", isDirectory: true)
    }

    static func crashReportsDirectory() -> URL? {
        bundleSupportDirectory()?.appendingPathComponent("CrashReports", isDirectory: true)
    }

    static func collegeDataDirectory() -> URL? {
        applicationSupportBase()?.appendingPathComponent("College", isDirectory: true)
    }

    static func googleDebugLogURL() -> URL? {
        bundleSupportDirectory()?.appendingPathComponent(GoogleDebugLog.fileName)
    }

    #if DEBUG
    static func unlockDebugLogURL() -> URL? {
        UnlockDebugLog.fileURL()
    }

    static func desktopDebugLogURL() -> URL? {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop/CollegeAppDebug.log")
    }
    #endif

    static let scalarUserDefaultsKeys: [String] = [
        "College.crash.pendingReportPath",
        "College.crash.latestReportPath",
        "College.crash.lastSeenSignalCrashMtime",
        "College.session.lastExitWasClean",
        RuntimeTelemetryMonitor.enabledKey,
        RuntimeTelemetryMonitor.heartbeatIntervalKey,
        RuntimeTelemetryMonitor.stallThresholdKey,
        "catalog.ingest.observability.v1",
        "catalog.review.queue.v1",
        "catalog.ingest.forceNext.v1",
        "catalog.ingest.gate.enabled",
        AssistantPlannerIndexingSettings.indexReadyKey,
        AssistantPlannerIndexingSettings.lastIndexedAtKey,
        AssistantPlannerIndexingSettings.lastChunkCountKey,
    ]

    static let userDefaultsKeyPrefixes: [String] = [
        "catalog.pdf.scrapeReport.v1.",
        "catalog.integrity.report.v1.",
        "catalog.ingest.checkpoint.v1.",
        "catalog.ingest.cancel.v1.",
        "catalog.ingest.signature.v1.",
        "catalog.pdf.health.",
        "catalog.integrity.",
    ]

    static var all: [DiagnosticsArtifact] {
        var items: [DiagnosticsArtifact] = []

        if let url = logsDirectory() {
            items.append(.init(id: "logs", title: "App Logs", kind: .directory, url: url, userDefaultsKeys: [], userDefaultsKeyPrefixes: []))
        }
        if let url = crashReportsDirectory() {
            items.append(.init(id: "crashes", title: "Crash Reports", kind: .directory, url: url, userDefaultsKeys: [
                "College.crash.pendingReportPath",
                "College.crash.latestReportPath",
                "College.crash.lastSeenSignalCrashMtime",
            ], userDefaultsKeyPrefixes: []))
        }
        if let url = diagnosticsDirectory() {
            items.append(.init(id: "diagnostics_root", title: "Diagnostics Store", kind: .directory, url: url, userDefaultsKeys: [], userDefaultsKeyPrefixes: []))
        }
        if let url = eventStoreURL() {
            items.append(.init(id: "event_store", title: "Event Timeline", kind: .file, url: url, userDefaultsKeys: [], userDefaultsKeyPrefixes: []))
        }
        if let url = launchHistoryURL() {
            items.append(.init(id: "launch_history", title: "Launch History", kind: .file, url: url, userDefaultsKeys: [], userDefaultsKeyPrefixes: []))
        }
        if let url = metricKitPayloadsDirectory() {
            items.append(.init(id: "metrickit", title: "MetricKit Payloads", kind: .directory, url: url, userDefaultsKeys: [], userDefaultsKeyPrefixes: []))
        }
        if let url = migratedReportsDirectory() {
            items.append(.init(id: "migrated_reports", title: "Migrated Diagnostic Reports", kind: .directory, url: url, userDefaultsKeys: [], userDefaultsKeyPrefixes: []))
        }
        if let url = collegeDataDirectory() {
            items.append(.init(id: "catalog_data", title: "Catalog Data", kind: .directory, url: url, userDefaultsKeys: [], userDefaultsKeyPrefixes: userDefaultsKeyPrefixes))
        }
        if let url = googleDebugLogURL() {
            items.append(.init(id: "google_debug", title: "Google Calendar Debug Log", kind: .file, url: url, userDefaultsKeys: [], userDefaultsKeyPrefixes: []))
        }
        #if DEBUG
        if let url = unlockDebugLogURL() {
            items.append(.init(id: "unlock_debug", title: "Unlock Debug Log", kind: .file, url: url, userDefaultsKeys: [], userDefaultsKeyPrefixes: []))
        }
        #endif

        items.append(.init(
            id: "catalog_userdefaults",
            title: "Catalog Diagnostic Keys",
            kind: .userDefaultsOnly,
            url: nil,
            userDefaultsKeys: scalarUserDefaultsKeys,
            userDefaultsKeyPrefixes: userDefaultsKeyPrefixes
        ))

        return items
    }

    static func allArtifactURLs(existingOnly: Bool = true) -> [URL] {
        let fm = FileManager.default
        return all.compactMap { artifact -> URL? in
            guard let url = artifact.url else { return nil }
            if existingOnly, !fm.fileExists(atPath: url.path) { return nil }
            return url
        }
    }

    static func wipeAllArtifacts() {
        let fm = FileManager.default
        for artifact in all {
            if let url = artifact.url {
                if artifact.kind == .directory {
                    try? fm.removeItem(at: url)
                } else if fm.fileExists(atPath: url.path) {
                    try? fm.removeItem(at: url)
                    try? fm.removeItem(at: url.appendingPathExtension("wal"))
                    try? fm.removeItem(at: url.appendingPathExtension("shm"))
                }
            }
        }
        let defaults = UserDefaults.standard
        for key in scalarUserDefaultsKeys {
            defaults.removeObject(forKey: key)
        }
        for key in defaults.dictionaryRepresentation().keys {
            for prefix in userDefaultsKeyPrefixes where key.hasPrefix(prefix) {
                defaults.removeObject(forKey: key)
            }
        }
    }
}
