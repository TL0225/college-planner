// AppLogger.swift
// Feature: Debug
// Purpose: Debug module — Entry.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import os

extension Notification.Name {
    /// Posted when `AppLogger` appends an entry to the log file.
    static let appLoggerDidAppendEntry = Notification.Name("AppLoggerDidAppendEntry")
}

/// Production-grade app logger:
/// - Writes newline-delimited JSON to Application Support (sandbox-safe)
/// - Rotates log files to cap disk usage
/// - Can capture stdout/stderr (so `print` and runtime warnings are preserved)
/// - Provides simple performance timing helpers
actor AppLogger {
    static let shared = AppLogger()

    nonisolated private static func iso8601String(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        return formatter.string(from: date)
    }

    enum Level: String, Codable {
        case trace
        case info
        case warning
        case error
        case fault

        fileprivate var osLogType: OSLogType {
            switch self {
            case .trace: return .debug
            case .info: return .info
            case .warning: return .error
            case .error: return .error
            case .fault: return .fault
            }
        }
    }

    enum Category: String, Codable, CaseIterable {
        case app
        case lifecycle
        case ui
        case navigation
        case persistence
        case network
        case calendar
        case google
        case scraper
        case intelligence
        case performance
        case runtime
        case system
    }

    struct Entry: Codable, Identifiable {
        let id: String
        let timestampISO8601: String
        let sessionID: String
        let level: Level
        let category: Category
        let message: String
        let metadata: [String: String]?
        let file: String?
        let function: String?
        let line: Int?
        let thread: String
        let process: String
        let osVersion: String
    }

    // MARK: - Configuration

    private let maxBytesPerFile: Int64 = 5 * 1024 * 1024   // 5 MB
    private let maxFiles: Int = 8

    // MARK: - State

    private let sessionID = UUID().uuidString
    private let startTime = Date()
    private let subsystem = Bundle.main.bundleIdentifier ?? "College"
    private lazy var osLogger = Logger(subsystem: subsystem, category: "AppLogger")

    private var logDirectoryURL: URL?
    private var currentLogURL: URL?
    private var redirectedConsoleURL: URL?

    private init() {
        let urls = Self.makeLogURLs()
        logDirectoryURL = urls.directory
        currentLogURL = urls.appLog
        redirectedConsoleURL = urls.consoleLog
        if let appLog = urls.appLog {
            Self.appendSessionHeader(to: appLog, sessionID: sessionID, started: startTime)
        }
    }

    // MARK: - Public API

    nonisolated func log(
        _ message: String,
        level: Level = .info,
        category: Category = .app,
        metadata: [String: String]? = nil,
        file: String = #fileID,
        function: String = #function,
        line: Int = #line
    ) {
        #if !DEBUG
        // Avoid high-volume debug logs in production builds.
        if level == .trace { return }
        #endif

        let thread = Thread.isMainThread ? "main" : "bg"
        Task {
            await self._log(
                message,
                level: level,
                category: category,
                metadata: metadata,
                thread: thread,
                file: file,
                function: function,
                line: line
            )
        }
    }

    nonisolated func trace(_ message: String, category: Category = .app, metadata: [String: String]? = nil, file: String = #fileID, function: String = #function, line: Int = #line) {
        log(message, level: .trace, category: category, metadata: metadata, file: file, function: function, line: line)
    }
    nonisolated func info(_ message: String, category: Category = .app, metadata: [String: String]? = nil, file: String = #fileID, function: String = #function, line: Int = #line) {
        log(message, level: .info, category: category, metadata: metadata, file: file, function: function, line: line)
    }
    nonisolated func warn(_ message: String, category: Category = .app, metadata: [String: String]? = nil, file: String = #fileID, function: String = #function, line: Int = #line) {
        log(message, level: .warning, category: category, metadata: metadata, file: file, function: function, line: line)
    }
    nonisolated func error(_ message: String, category: Category = .app, metadata: [String: String]? = nil, file: String = #fileID, function: String = #function, line: Int = #line) {
        log(message, level: .error, category: category, metadata: metadata, file: file, function: function, line: line)
    }
    nonisolated func fault(_ message: String, category: Category = .app, metadata: [String: String]? = nil, file: String = #fileID, function: String = #function, line: Int = #line) {
        log(message, level: .fault, category: category, metadata: metadata, file: file, function: function, line: line)
    }

    /// Captures stdout/stderr into `console.log` in the log directory.
    /// Call early in app launch (best-effort; safe to call multiple times).
    nonisolated func redirectConsoleOutput() {
        #if DEBUG
        Task { await self._redirectConsoleOutputIfNeeded() }
        #endif
    }

    /// Returns the current log file URL.
    func logFileURL() -> URL? { currentLogURL }

    /// Returns the log directory URL.
    func logsDirectoryURL() -> URL? { logDirectoryURL }

    /// Deletes all log files.
    func clearLogs() async {
        guard let dir = logDirectoryURL else { return }
        let fm = FileManager.default
        let urls = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        for url in urls {
            try? fm.removeItem(at: url)
        }
        let urls2 = Self.makeLogURLs()
        logDirectoryURL = urls2.directory
        currentLogURL = urls2.appLog
        redirectedConsoleURL = urls2.consoleLog
        if let appLog = urls2.appLog {
            Self.appendSessionHeader(to: appLog, sessionID: sessionID, started: startTime)
        }
    }

    /// Read the most recent log lines (best-effort), decoded as JSON entries.
    func readRecentEntries(maxBytes: Int = 512 * 1024) async -> [Entry] {
        guard let url = currentLogURL else { return [] }
        guard let data = readFileTail(url: url, maxBytes: maxBytes) else { return [] }

        let text = String(data: data, encoding: .utf8) ?? ""
        let lines = text.split(separator: "\n")
        var out: [Entry] = []
        out.reserveCapacity(min(lines.count, 800))

        let decoder = JSONDecoder()
        for line in lines {
            guard line.first == "{" else { continue }
            if let d = String(line).data(using: .utf8),
               let entry = try? decoder.decode(Entry.self, from: d) {
                out.append(entry)
            }
        }
        return out
    }

    // MARK: - Performance helpers

    nonisolated func measure<T>(
        _ name: String,
        category: Category = .performance,
        metadata: [String: String]? = nil,
        file: String = #fileID,
        function: String = #function,
        line: Int = #line,
        work: () throws -> T
    ) rethrows -> T {
        let start = Date()
        do {
            let value = try work()
            let ms = Int((Date().timeIntervalSince(start) * 1000.0).rounded())
            log(
                "perf:\(name) \(ms)ms",
                level: .info,
                category: category,
                metadata: Self.mergeMetadata(metadata, ["duration_ms": "\(ms)"]),
                file: file,
                function: function,
                line: line
            )
            return value
        } catch {
            let ms = Int((Date().timeIntervalSince(start) * 1000.0).rounded())
            log(
                "perf:\(name) failed \(ms)ms: \(error.localizedDescription)",
                level: .error,
                category: category,
                metadata: Self.mergeMetadata(metadata, ["duration_ms": "\(ms)"]),
                file: file,
                function: function,
                line: line
            )
            throw error
        }
    }

    nonisolated func measure<T>(
        _ name: String,
        category: Category = .performance,
        metadata: [String: String]? = nil,
        file: String = #fileID,
        function: String = #function,
        line: Int = #line,
        work: () async throws -> T
    ) async rethrows -> T {
        let start = Date()
        do {
            let value = try await work()
            let ms = Int((Date().timeIntervalSince(start) * 1000.0).rounded())
            log(
                "perf:\(name) \(ms)ms",
                level: .info,
                category: category,
                metadata: Self.mergeMetadata(metadata, ["duration_ms": "\(ms)"]),
                file: file,
                function: function,
                line: line
            )
            return value
        } catch {
            let ms = Int((Date().timeIntervalSince(start) * 1000.0).rounded())
            log(
                "perf:\(name) failed \(ms)ms: \(error.localizedDescription)",
                level: .error,
                category: category,
                metadata: Self.mergeMetadata(metadata, ["duration_ms": "\(ms)"]),
                file: file,
                function: function,
                line: line
            )
            throw error
        }
    }

    // MARK: - Internals

    private func _log(
        _ message: String,
        level: Level,
        category: Category,
        metadata: [String: String]?,
        thread: String,
        file: String,
        function: String,
        line: Int
    ) async {
        rotateIfNeeded()

        let now = Date()
        let ts = iso8601(now)
        let fileShort = file.split(separator: "/").last.map(String.init) ?? file

        let sanitizedMessage = Self.sanitize(message)
        let sanitizedMetadata = Self.sanitize(metadata)

        let entry = Entry(
            id: UUID().uuidString,
            timestampISO8601: ts,
            sessionID: sessionID,
            level: level,
            category: category,
            message: sanitizedMessage,
            metadata: sanitizedMetadata,
            file: fileShort,
            function: function,
            line: line,
            thread: thread,
            process: ProcessInfo.processInfo.processName,
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString
        )

        // Unified logging (great for Instruments + system log collection).
        osLogger.log(level: level.osLogType, "\(category.rawValue, privacy: .public): \(sanitizedMessage, privacy: .private)")

        guard let url = currentLogURL else { return }
        guard let data = encodeJSONLine(entry) else { return }
        append(data: data, to: url)

        // Notify UI listeners (best-effort). Keep this on the main thread so SwiftUI updates are safe.
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .appLoggerDidAppendEntry, object: nil)
        }
    }

    private struct LogURLs {
        let directory: URL?
        let appLog: URL?
        let consoleLog: URL?
    }

    private static func makeLogURLs() -> LogURLs {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let bundleID = Bundle.main.bundleIdentifier ?? "College"
        let dir = base?.appendingPathComponent(bundleID, isDirectory: true).appendingPathComponent("Logs", isDirectory: true)
        if let dir {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        let finalDir = dir ?? fm.temporaryDirectory
        return LogURLs(
            directory: finalDir,
            appLog: finalDir.appendingPathComponent("app.log"),
            consoleLog: finalDir.appendingPathComponent("console.log")
        )
    }

    private static func appendSessionHeader(to url: URL, sessionID: String, started: Date) {
        let header: [String: String] = [
            "type": "session_start",
            "session": sessionID,
            "started": Self.iso8601String(started),
            "os": ProcessInfo.processInfo.operatingSystemVersionString,
            "process": ProcessInfo.processInfo.processName
        ]
        if let line = (try? JSONSerialization.data(withJSONObject: header)) {
            if let handle = try? FileHandle(forWritingTo: url) {
                do {
                    try handle.seekToEnd()
                    try handle.write(contentsOf: line + Data([0x0A]))
                    try handle.close()
                } catch {
                    try? handle.close()
                }
            } else {
                try? (line + Data([0x0A])).write(to: url, options: .atomic)
            }
        }
    }

    private func rotateIfNeeded() {
        guard let url = currentLogURL else { return }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        guard size >= maxBytesPerFile else { return }

        let fm = FileManager.default
        let ts = iso8601(Date()).replacingOccurrences(of: ":", with: "-")
        let rotated = url.deletingLastPathComponent().appendingPathComponent("app-\(ts).log")
        try? fm.moveItem(at: url, to: rotated)

        // Prune old logs.
        guard let dir = logDirectoryURL else { return }
        let urls = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey], options: [])) ?? []
        let logURLs = urls.filter { $0.lastPathComponent.hasPrefix("app") && $0.pathExtension == "log" }
        let sorted = logURLs.sorted {
            let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return a > b
        }

        if sorted.count > maxFiles {
            for u in sorted.suffix(from: maxFiles) {
                try? fm.removeItem(at: u)
            }
        }

        // Start a new file and header.
        if let fresh = currentLogURL {
            Self.appendSessionHeader(to: fresh, sessionID: sessionID, started: startTime)
        }
    }

    private func append(data: Data, to url: URL) {
        if let handle = try? FileHandle(forWritingTo: url) {
            do {
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try handle.close()
            } catch {
                try? handle.close()
            }
        } else {
            try? data.write(to: url, options: .atomic)
        }
    }

    private func encodeJSONLine(_ entry: Entry) -> Data? {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(entry) {
            return data + Data([0x0A])
        }
        return nil
    }

    private func iso8601(_ date: Date) -> String {
        Self.iso8601String(date)
    }

    private static func mergeMetadata(_ a: [String: String]?, _ b: [String: String]) -> [String: String] {
        var out = a ?? [:]
        for (k, v) in b { out[k] = v }
        return out
    }

    private func readFileTail(url: URL, maxBytes: Int) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let start = max(0, size - maxBytes)
        do {
            try handle.seek(toOffset: UInt64(start))
            return try handle.readToEnd()
        } catch {
            return nil
        }
    }

    private func _redirectConsoleOutputIfNeeded() async {
        guard let consoleURL = redirectedConsoleURL else { return }

        // Create the file if needed.
        FileManager.default.createFile(atPath: consoleURL.path, contents: nil)

        // Redirect stdout/stderr to the file (best-effort).
        // Note: avoid repeatedly redirecting if called multiple times.
        // We can't reliably detect current redirection state, so this is idempotent enough.
        if let fh = try? FileHandle(forWritingTo: consoleURL) {
            do {
                try fh.seekToEnd()
                dup2(fh.fileDescriptor, STDOUT_FILENO)
                dup2(fh.fileDescriptor, STDERR_FILENO)
                // Keep fh open so descriptors remain valid.
            } catch {
                // Ignore failures.
            }
        }

        await _log(
            "Console output redirected to console.log",
            level: .info,
            category: .system,
            metadata: nil,
            thread: "bg",
            file: #fileID,
            function: #function,
            line: #line
        )
    }

    // MARK: - Redaction

    private static func sanitize(_ message: String) -> String {
        var s = message

        // Email addresses.
        s = s.replacingOccurrences(
            of: #"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b"#,
            with: "[REDACTED_EMAIL]",
            options: .regularExpression
        )

        // Authorization headers / Bearer tokens.
        s = s.replacingOccurrences(
            of: #"(?i)\bBearer\s+[A-Za-z0-9\-\._~\+\/]+=*"#,
            with: "Bearer [REDACTED_TOKEN]",
            options: .regularExpression
        )

        // Common JSON key patterns for secrets/tokens.
        let secretKeys = [
            "access_token", "refresh_token", "id_token",
            "api_key", "x-api-key", "authorization", "client_secret"
        ]
        for key in secretKeys {
            s = s.replacingOccurrences(
                of: #"(?i)("\#(key)"\s*:\s*")([^"]+)(")"#,
                with: #"$1[REDACTED]$3"#,
                options: .regularExpression
            )
            s = s.replacingOccurrences(
                of: #"(?i)(\#(key)\s*=\s*)([^\s&]+)"#,
                with: #"$1[REDACTED]"#,
                options: .regularExpression
            )
        }

        // Very long "token-like" strings.
        s = s.replacingOccurrences(
            of: #"[A-Za-z0-9_\-]{32,}"#,
            with: "[REDACTED]",
            options: .regularExpression
        )

        return s
    }

    private static func sanitize(_ metadata: [String: String]?) -> [String: String]? {
        guard var md = metadata, !md.isEmpty else { return metadata }

        // Drop obviously sensitive keys entirely.
        let deny = Set(["authorization", "token", "access_token", "refresh_token", "id_token", "api_key", "x-api-key", "client_secret"])
        for k in md.keys {
            if deny.contains(k.lowercased()) {
                md[k] = "[REDACTED]"
            }
        }

        for (k, v) in md {
            md[k] = sanitize(v)
        }

        return md
    }
}

