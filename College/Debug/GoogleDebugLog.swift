// GoogleDebugLog.swift
// Feature: Debug
// Purpose: Debug module — GoogleDebugLog.
// Data: CollegePersistence / repositories when applicable.

import Foundation
#if canImport(AppKit)
import AppKit
#endif

enum GoogleDebugLog {
    static let fileName = "College-GoogleCalendar-Debug.txt"
    private static let isoFormatterLock = NSLock()
    nonisolated(unsafe) private static let isoFormatter = ISO8601DateFormatter()

    private static func isoTimestamp(_ date: Date) -> String {
        isoFormatterLock.lock()
        defer { isoFormatterLock.unlock() }
        return isoFormatter.string(from: date)
    }

    /// Location inside the app container (Application Support), which is writable under the sandbox.
    static func fileURL() -> URL? {
        let fm = FileManager.default

        // For sandboxed apps, this resolves inside the container.
        guard let base = try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else {
            return nil
        }

        let bundleID = Bundle.main.bundleIdentifier ?? "College"
        let dir = base.appendingPathComponent(bundleID, isDirectory: true)
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            return nil
        }

        return dir.appendingPathComponent(fileName)
    }

    static func ensureFileExists() {
        guard let url = fileURL() else { return }
        let fm = FileManager.default
        guard !fm.fileExists(atPath: url.path) else { return }

        let header = "=== College Google Calendar Debug Log ===\nstarted=\(isoTimestamp(Date()))\n===\n\n"
        try? header.write(to: url, atomically: true, encoding: .utf8)
    }

    #if canImport(AppKit)
    static func revealInFinder() {
        guard let url = fileURL() else { return }
        ensureFileExists()
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
    #endif
}
