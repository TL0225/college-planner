// FSWatchdogService.swift
// Feature: Core
// Purpose: Core module — FSWatchdogService.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import Combine
import CoreServices
import AppKit

// MARK: - FSWatchdogService

/// Watches macOS folders using FSEventStream and auto-classifies new academic files
/// via `DocumentClassifierService`, then surfaces results as in-app notifications.
@MainActor
final class FSWatchdogService: ObservableObject {

    // MARK: - Singleton

    static let shared = FSWatchdogService()

    // MARK: - Published Properties

    @Published var isWatching: Bool = false
    @Published var watchedPaths: [String] = []
    @Published var lastDetectedFile: URL? = nil

    // MARK: - Private Properties

    private var eventStream: FSEventStreamRef?

    private static let academicExtensions: Set<String> = [
        "pdf", "docx", "doc", "jpg", "jpeg", "png"
    ]

    private static let defaultsKey = "watchdog.watchedPaths"

    private static let kDebounceLatency: CFTimeInterval = 1.5

    // MARK: - Init

    private init() {
        loadWatchedPaths()
    }

    // MARK: - UserDefaults Persistence

    private func loadWatchedPaths() {
        if let saved = UserDefaults.standard.stringArray(forKey: Self.defaultsKey), !saved.isEmpty {
            watchedPaths = saved
        } else {
            watchedPaths = [
                NSHomeDirectory() + "/Downloads",
                NSHomeDirectory() + "/Desktop"
            ]
        }
    }

    private func saveWatchedPaths() {
        UserDefaults.standard.set(watchedPaths, forKey: Self.defaultsKey)
    }

    // MARK: - Public API

    /// Start watching all paths in `watchedPaths`. Restarts any existing stream.
    func startWatching() {
        stopWatching()
        guard !watchedPaths.isEmpty else { return }

        // Attempt security-scoped resource access for any stored bookmarks.
        activateSecurityBookmarks()

        let cfPaths = watchedPaths as CFArray

        // The callback needs an unretained pointer to self. Since this is a
        // singleton, self is always alive for the lifetime of the stream.
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        var context = FSEventStreamContext(
            version: 0,
            info: selfPtr,
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagUseCFTypes |
            kFSEventStreamCreateFlagFileEvents |
            kFSEventStreamCreateFlagNoDefer
        )

        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            FSWatchdogService.fsEventCallback,
            &context,
            cfPaths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            Self.kDebounceLatency,
            flags
        ) else {
            print("[FSWatchdogService] Failed to create FSEventStream.")
            return
        }

        FSEventStreamSetDispatchQueue(stream, DispatchQueue.global(qos: .utility))
        FSEventStreamStart(stream)
        eventStream = stream
        isWatching = true
        print("[FSWatchdogService] Started watching: \(watchedPaths)")
    }

    /// Stop watching and tear down the FSEventStream.
    func stopWatching() {
        guard let stream = eventStream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        eventStream = nil
        isWatching = false
        print("[FSWatchdogService] Stopped watching.")
    }

    /// Add a new path to the watch list.  Restarts the stream if already active.
    func addWatchedPath(_ path: String) {
        guard !watchedPaths.contains(path) else { return }
        watchedPaths.append(path)
        saveWatchedPaths()
        if isWatching { startWatching() }
    }

    /// Remove a path from the watch list.  Restarts (or stops) the stream as needed.
    func removeWatchedPath(_ path: String) {
        watchedPaths.removeAll { $0 == path }
        saveWatchedPaths()
        if isWatching {
            watchedPaths.isEmpty ? stopWatching() : startWatching()
        }
    }

    // MARK: - Internal File Handling

    /// Entry point called for each newly-created qualifying file.
    func handleNewFile(at url: URL) async {
        let ext = url.pathExtension.lowercased()
        guard Self.academicExtensions.contains(ext) else { return }

        // Skip hidden or system files.
        let name = url.lastPathComponent
        guard !name.hasPrefix(".") else { return }

        lastDetectedFile = url

        print("[FSWatchdogService] Classifying: \(url.lastPathComponent)")

        let result = await DocumentClassifierService.shared.classify(fileURL: url)

        let courseTag = result.courseCode.map { " · \($0)" } ?? ""
        let weekTag   = result.weekNumber.map { " (Week \($0))" } ?? ""
        let title     = "New \(result.documentType.displayName) Detected\(courseTag)"
        let message   = "\(result.suggestedName)\(weekTag)"

        AppNotificationCenter.shared.post(
            kind: .info,
            title: title,
            message: message,
            isDismissible: true,
            autoDismissAfter: 6.0
        )
    }

    // MARK: - Sandbox / Security-Scoped Bookmarks

    /// Activate any previously-stored security-scoped bookmarks for sandboxed access.
    private func activateSecurityBookmarks() {
        let bookmarksKey = "watchdog.securityBookmarks"
        guard let bookmarkDict = UserDefaults.standard.dictionary(forKey: bookmarksKey) as? [String: Data] else {
            return
        }
        for (path, bookmarkData) in bookmarkDict {
            var isStale = false
            if let url = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                _ = url.startAccessingSecurityScopedResource()
                if isStale {
                    print("[FSWatchdogService] Stale bookmark for: \(path)")
                }
            }
        }
    }

    /// Store a security-scoped bookmark for `url` (call from an NSOpenPanel result).
    func storeSecurityBookmark(for url: URL) {
        let bookmarksKey = "watchdog.securityBookmarks"
        var bookmarkDict = (UserDefaults.standard.dictionary(forKey: bookmarksKey) as? [String: Data]) ?? [:]
        if let data = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            bookmarkDict[url.path] = data
            UserDefaults.standard.set(bookmarkDict, forKey: bookmarksKey)
        }
    }

    // MARK: - FSEventStream C Callback

    /// Static C-compatible callback.  Scheduled on the main run loop, so event
    /// delivery already happens on the main thread; we still hop through
    /// `Task { @MainActor in ... }` for Swift-concurrency correctness.
    private static let fsEventCallback: FSEventStreamCallback = {
        (_, clientInfo, numEvents, eventPaths, eventFlags, _) in

        guard let clientInfo else { return }

        // passUnretained — the singleton is always alive.
        let service = Unmanaged<FSWatchdogService>.fromOpaque(clientInfo).takeUnretainedValue()

        // With kFSEventStreamCreateFlagUseCFTypes the event path payload is CFArray<CFString>.
        // Decode conservatively and validate bounds to avoid undefined behavior if payload is malformed.
        let cfArray = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue()
        let pathsArray = cfArray as NSArray
        guard pathsArray.count >= Int(numEvents) else { return }

        for i in 0..<numEvents {
            let flags = eventFlags[i]
            guard let path = pathsArray[Int(i)] as? String else { continue }

            let isCreated = (flags & UInt32(kFSEventStreamEventFlagItemCreated))   != 0
            let isFile    = (flags & UInt32(kFSEventStreamEventFlagItemIsFile))     != 0
            let isRemoved = (flags & UInt32(kFSEventStreamEventFlagItemRemoved))    != 0

            guard isCreated && isFile && !isRemoved else { continue }

            let url = URL(fileURLWithPath: path)

            // Verify the file actually exists (avoids reacting to transient temp files).
            guard FileManager.default.fileExists(atPath: path) else { continue }

            Task { @MainActor in
                await service.handleNewFile(at: url)
            }
        }
    }
}

// MARK: - @unchecked Sendable

// FSWatchdogService is @MainActor-isolated; all mutable state is protected.
// The Unmanaged pointer in the C callback is read-only and the referenced
// object is the singleton, so cross-actor capture is safe.
extension FSWatchdogService: @unchecked Sendable {}
