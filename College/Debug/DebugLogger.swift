import Foundation
import os

/// Simple file-based logger for debugging when Xcode console isn't available
class DebugLogger: @unchecked Sendable {
    nonisolated static let shared = DebugLogger()
    
    enum Level: String {
        case trace = "TRACE"
        case info = "INFO"
        case warn = "WARN"
        case error = "ERROR"
    }

    enum Category: String {
        case app = "APP"
        case lifecycle = "LIFECYCLE"
        case ui = "UI"
        case navigation = "NAV"
        case coreData = "COREDATA"
        case network = "NETWORK"
        case scraper = "SCRAPER"
        case intelligence = "INTELLIGENCE"
        case system = "SYSTEM"
    }

    nonisolated(unsafe) private var logFileURL: URL?
    /// Persistent write handle — opened once and held open to avoid repeated open/close syscalls.
    nonisolated(unsafe) private var logFileHandle: FileHandle?
    nonisolated private let queue = DispatchQueue(label: "com.college.debuglogger", qos: .utility)
    nonisolated private let sessionID = UUID().uuidString
    nonisolated private let startTime = Date()
    nonisolated private let osLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "College", category: "DebugLogger")
    
    nonisolated private init() {
        #if DEBUG
        // Prefer writing the debug log to the Desktop (matches existing debug docs/workflow),
        // but fall back to Application Support inside the app container if Desktop isn't writable.
        let fm = FileManager.default
        let bundleID = Bundle.main.bundleIdentifier ?? "College"
        
        func ensureDir(_ url: URL) -> URL? {
            do {
                try fm.createDirectory(at: url, withIntermediateDirectories: true)
                return url
            } catch {
                return nil
            }
        }
        
        let desktopDir = ensureDir(fm.homeDirectoryForCurrentUser.appendingPathComponent("Desktop", isDirectory: true))
        let appSupportBase = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let appSupportDir = appSupportBase.flatMap { ensureDir($0.appendingPathComponent(bundleID, isDirectory: true)) }
        
        // Choose Desktop if we can write there; otherwise use sandbox-safe app support; otherwise temp.
        let preferredDir = desktopDir ?? appSupportDir ?? fm.temporaryDirectory
        let fileURL = preferredDir.appendingPathComponent("CollegeAppDebug.log")
        logFileURL = fileURL

        // Clear old log on app launch
        let header = """
        === College App Debug Log ===
        session=\(sessionID)
        started=\(DebugLogger.formatTimestamp(startTime))
        os=\(ProcessInfo.processInfo.operatingSystemVersionString)
        process=\(ProcessInfo.processInfo.processName)
        ===

        """
        do {
            try header.write(to: fileURL, atomically: true, encoding: .utf8)
            // Open the handle once and keep it open for the session — avoids open/close on every write.
            logFileHandle = try FileHandle(forWritingTo: fileURL)
            logFileHandle?.seekToEndOfFile()
        } catch {
            // If Desktop write fails unexpectedly, fall back to a sandbox-safe location.
            if preferredDir == desktopDir, let fallbackDir = appSupportDir ?? ensureDir(fm.temporaryDirectory) {
                let fallbackURL = fallbackDir.appendingPathComponent("CollegeAppDebug.log")
                try? header.write(to: fallbackURL, atomically: true, encoding: .utf8)
                logFileURL = fallbackURL
                logFileHandle = try? FileHandle(forWritingTo: fallbackURL)
                logFileHandle?.seekToEndOfFile()
            }
        }

        print("[DebugLogger] Debug log file: \(fileURL.path)")

        // Emit a consistent first line after the header.
        log("Session marker: logger ready", category: .system, level: .info)
        #else
        // In Release builds, avoid file logging to reduce overhead and prevent accidental data leakage.
        logFileURL = nil
        #endif
    }

    /// Backwards-compatible entrypoint.
    /// Prefer `log(_:category:level:file:function:line:)` for structured logs.
    nonisolated func log(_ message: String) {
        log(message, category: .system, level: .info)
    }

    nonisolated func log(
        _ message: String,
        category: Category,
        level: Level = .info,
        file: String = #fileID,
        function: String = #function,
        line: Int = #line
    ) {
        #if !DEBUG
        // In Release builds, reduce log volume to minimize data leakage and overhead.
        if level == .trace || level == .info { return }
        #endif

        // Always forward into the production logger (Release-safe, rotated, persisted).
        AppLogger.shared.log(
            message,
            level: {
                switch level {
                case .trace: return .trace
                case .info: return .info
                case .warn: return .warning
                case .error: return .error
                }
            }(),
            category: {
                switch category {
                case .app: return .app
                case .lifecycle: return .lifecycle
                case .ui: return .ui
                case .navigation: return .navigation
                case .coreData: return .coreData
                case .network: return .network
                case .scraper: return .scraper
                case .intelligence: return .intelligence
                case .system: return .system
                }
            }(),
            metadata: nil,
            file: file,
            function: function,
            line: line
        )

        // In non-debug builds, keep logging minimal and avoid extra formatting overhead.
        #if !DEBUG
        osLogger.debug("\(message, privacy: .private)")
        return
        #endif

        let now = Date()
        let ts = DebugLogger.formatTimestamp(now)
        let elapsed = String(format: "%.3fs", now.timeIntervalSince(startTime))
        let thread = Thread.isMainThread ? "main" : "bg"
        let fileName = file.split(separator: "/").last.map(String.init) ?? file

        let logMessage = "[\(ts) +\(elapsed)] [\(level.rawValue)] [\(category.rawValue)] [\(thread)] \(fileName):\(line) \(function) — \(message)\n"

        // Always emit to unified logging (respects system log levels).
        osLogger.debug("\(logMessage, privacy: .private)")

        #if DEBUG
        // Write to file on background queue using the persistent handle — no open/close per call.
        guard logFileURL != nil else { return }
        queue.async { [weak self] in
            guard let self else { return }
            if let handle = self.logFileHandle, let data = logMessage.data(using: .utf8) {
                handle.write(data)
            }
        }
        #endif
    }

    /// Best-effort flush (useful right before exporting/sharing a log).
    ///
    /// Note: our writes are performed on a serial queue; flushing just waits for pending work.
    nonisolated func flush(timeoutSeconds: Double = 2.0) {
        let group = DispatchGroup()
        group.enter()
        queue.async {
            group.leave()
        }
        _ = group.wait(timeout: .now() + timeoutSeconds)
    }
    
    nonisolated func logSection(_ title: String) {
        log("\n========== \(title) ==========", category: .system, level: .info)
    }
    
    nonisolated func logError(_ error: Error) {
        log("❌ ERROR: \(error)", category: .system, level: .error)
        log("Type: \(type(of: error))", category: .system, level: .error)
        log("Description: \(error.localizedDescription)", category: .system, level: .error)
    }

    // MARK: - Convenience helpers

    nonisolated func app(_ message: String, level: Level = .info, file: String = #fileID, function: String = #function, line: Int = #line) {
        log(message, category: .app, level: level, file: file, function: function, line: line)
    }

    nonisolated func lifecycle(_ message: String, level: Level = .info, file: String = #fileID, function: String = #function, line: Int = #line) {
        log(message, category: .lifecycle, level: level, file: file, function: function, line: line)
    }

    nonisolated func ui(_ message: String, level: Level = .info, file: String = #fileID, function: String = #function, line: Int = #line) {
        log(message, category: .ui, level: level, file: file, function: function, line: line)
    }

    nonisolated func nav(_ message: String, level: Level = .info, file: String = #fileID, function: String = #function, line: Int = #line) {
        log(message, category: .navigation, level: level, file: file, function: function, line: line)
    }

    nonisolated func coreData(_ message: String, level: Level = .info, file: String = #fileID, function: String = #function, line: Int = #line) {
        log(message, category: .coreData, level: level, file: file, function: function, line: line)
    }

    nonisolated func network(_ message: String, level: Level = .info, file: String = #fileID, function: String = #function, line: Int = #line) {
        log(message, category: .network, level: level, file: file, function: function, line: line)
    }

    nonisolated func scraper(_ message: String, level: Level = .info, file: String = #fileID, function: String = #function, line: Int = #line) {
        log(message, category: .scraper, level: level, file: file, function: function, line: line)
    }

    nonisolated func intelligence(_ message: String, level: Level = .info, file: String = #fileID, function: String = #function, line: Int = #line) {
        log(message, category: .intelligence, level: level, file: file, function: function, line: line)
    }

    private nonisolated static func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        formatter.timeZone = .current
        return formatter.string(from: date)
    }
}
