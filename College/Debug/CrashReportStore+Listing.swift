// CrashReportStore+Listing.swift
// Feature: Debug
// Purpose: List crash report artifacts for the Diagnostics Center.

import Foundation

extension CrashReportStore {
    static func allReportURLs(since: Date? = nil) -> [URL] {
        guard let dir = crashReportsDirectoryURL() else { return [] }
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return files
            .filter { $0.pathExtension == "json" && $0.lastPathComponent.hasPrefix("crash_") }
            .filter { url in
                guard let since else { return true }
                let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return mtime >= since
            }
            .sorted { lhs, rhs in
                let l = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let r = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return l > r
            }
    }

    private static func crashReportsDirectoryURL() -> URL? {
        let fm = FileManager.default
        guard let appSupport = try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ) else { return nil }
        let bundleID = Bundle.main.bundleIdentifier ?? "College"
        return appSupport
            .appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("CrashReports", isDirectory: true)
    }
}
