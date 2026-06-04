// UnlockDebugLog.swift
// Feature: Debug
// Purpose: Debug module — Mark.
// Data: CollegePersistence / repositories when applicable.

import Foundation
#if canImport(AppKit)
import AppKit
#endif

/// DEBUG helper for investigating post-auth blank/white window.
///
/// Notes on sandboxing:
/// - The app is sandboxed, so writing directly to Desktop usually fails unless the user has granted access.
/// - We attempt Desktop first for convenience; if that fails, we fall back to Application Support (container-safe).
#if DEBUG
enum UnlockDebugLog {
    nonisolated static let fileName = "College-Unlock-Debug.txt"
    nonisolated private static let bookmarkDefaultsKey = "unlockDebugLog.bookmark.v1"

    nonisolated private static let queue = DispatchQueue(label: "College.UnlockDebugLog")
    nonisolated private static let isoFormatterLock = NSLock()
    nonisolated(unsafe) private static let isoFormatter = ISO8601DateFormatter()

    nonisolated private static func isoTimestamp(_ date: Date) -> String {
        isoFormatterLock.lock()
        defer { isoFormatterLock.unlock() }
        return isoFormatter.string(from: date)
    }

    nonisolated static func log(_ message: String) {
        queue.async {
            let timestamp = isoTimestamp(Date())
            let line = "[\(timestamp)] \(message)\n"
            let data = line.data(using: .utf8) ?? Data()

            guard let destination = resolveDestination() else { return }
            defer {
                if destination.startedSecurityScope {
                    destination.url.stopAccessingSecurityScopedResource()
                }
            }

            ensureFileExists(at: destination.url, source: destination.source)

            do {
                if FileManager.default.fileExists(atPath: destination.url.path) {
                    let handle = try FileHandle(forWritingTo: destination.url)
                    try handle.seekToEnd()
                    try handle.write(contentsOf: data)
                    try handle.close()
                } else {
                    try data.write(to: destination.url, options: .atomic)
                }
            } catch {
                if destination.source == "bookmark" {
                    clearBookmark()
                }
                // Ignore logging failures.
            }
        }
    }

    nonisolated static func fileURL() -> URL? {
        resolveDestination()?.url
    }

    nonisolated static func resolvedPathDescription() -> String {
        guard let destination = resolveDestination() else { return "<none>" }
        if destination.startedSecurityScope {
            destination.url.stopAccessingSecurityScopedResource()
        }
        return "source=\(destination.source) path=\(destination.url.path)"
    }

    nonisolated static func ensureFileExists() {
        guard let destination = resolveDestination() else { return }
        defer {
            if destination.startedSecurityScope {
                destination.url.stopAccessingSecurityScopedResource()
            }
        }
        ensureFileExists(at: destination.url, source: destination.source)
    }

    nonisolated private static func ensureFileExists(at url: URL, source: String) {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: url.path) else { return }

        let header = "=== College Unlock Debug Log ===\nstarted=\(isoTimestamp(Date()))\nsource=\(source)\npath=\(url.path)\n===\n\n"
        do {
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try header.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            // Ignore.
        }
    }

    nonisolated private static func resolveDestination() -> (url: URL, source: String, startedSecurityScope: Bool)? {
        if let bookmarked = resolveBookmarkedURL() {
            return bookmarked
        }

        // 1) Preferred: Desktop (nice for quick sharing)
        let desktopURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop", isDirectory: true)
            .appendingPathComponent(fileName)

        if canWrite(to: desktopURL) {
            return (url: desktopURL, source: "desktop", startedSecurityScope: false)
        }

        // 2) Fallback: Application Support (sandbox-safe)
        let fm = FileManager.default
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
        return (url: dir.appendingPathComponent(fileName), source: "appSupport", startedSecurityScope: false)
    }

    nonisolated private static func resolveBookmarkedURL() -> (url: URL, source: String, startedSecurityScope: Bool)? {
        let defaults = UserDefaults.standard
        guard let data = defaults.data(forKey: bookmarkDefaultsKey) else { return nil }

        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return nil
        }

        if isStale {
            clearBookmark()
            return nil
        }

        let didStart = url.startAccessingSecurityScopedResource()
        return (url: url, source: "bookmark", startedSecurityScope: didStart)
    }

    nonisolated private static func clearBookmark() {
        UserDefaults.standard.removeObject(forKey: bookmarkDefaultsKey)
    }

    nonisolated private static func canWrite(to fileURL: URL) -> Bool {
        let dir = fileURL.deletingLastPathComponent()
        var isDir: ObjCBool = false
        let fm = FileManager.default

        if !fm.fileExists(atPath: dir.path, isDirectory: &isDir) {
            // Try to create the directory. If sandbox blocks it, this will fail.
            do {
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            } catch {
                return false
            }
        }

        // Try a lightweight write test.
        let probeURL = dir.appendingPathComponent(".college_unlock_log_probe")
        do {
            try Data("probe".utf8).write(to: probeURL, options: .atomic)
            try? fm.removeItem(at: probeURL)
            return true
        } catch {
            return false
        }
    }

    #if canImport(AppKit)
    @MainActor
    static func chooseLogFileLocation() {
        let panel = NSSavePanel()
        panel.title = "Choose Unlock Debug Log Location"
        panel.nameFieldStringValue = fileName
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop", isDirectory: true)

        if panel.runModal() == .OK, let url = panel.url {
            if let bookmark = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) {
                UserDefaults.standard.set(bookmark, forKey: bookmarkDefaultsKey)
                log("UnlockDebugLog: configured bookmark -> \(url.path)")
            }
        }
    }

    static func revealInFinder() {
        guard let destination = resolveDestination() else { return }
        defer {
            if destination.startedSecurityScope {
                destination.url.stopAccessingSecurityScopedResource()
            }
        }
        ensureFileExists(at: destination.url, source: destination.source)
        NSWorkspace.shared.activateFileViewerSelecting([destination.url])
    }
    #endif
}

/// DEBUG helper for measuring post-unlock render gaps.
#if DEBUG
enum UnlockDebugTiming {
    private struct Mark {
        let token: UUID
        let date: Date
    }

    private static let queue = DispatchQueue(label: "College.UnlockDebugTiming")
    nonisolated(unsafe) private static var mainContentEnabledMark: Mark?

    /// Called when `ContentView` flips `allowMainContent = true`.
    static func markMainContentEnabled(token: UUID) {
        queue.async {
            mainContentEnabledMark = Mark(token: token, date: Date())
        }
    }

    /// Returns elapsed seconds since `markMainContentEnabled` and clears the mark.
    static func consumeMainContentEnabledElapsed() -> (token: UUID, seconds: TimeInterval)? {
        queue.sync {
            guard let mark = mainContentEnabledMark else { return nil }
            mainContentEnabledMark = nil
            return (token: mark.token, seconds: Date().timeIntervalSince(mark.date))
        }
    }
}
#endif
#endif
