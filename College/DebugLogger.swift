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

    private let logFileURL: URL?
    private let queue = DispatchQueue(label: "com.college.debuglogger", qos: .utility)
    private let sessionID = UUID().uuidString
    private let startTime = Date()
    private let osLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "College", category: "DebugLogger")
    
    private init() {
        #if DEBUG
        // Desktop is not writable under the sandbox by default.
        // Write into Application Support (inside the app container) so logs are always creatable.
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let bundleID = Bundle.main.bundleIdentifier ?? "College"
        let dir = base?.appendingPathComponent(bundleID, isDirectory: true)
        if let dir {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        let fileURL = (dir ?? fm.temporaryDirectory).appendingPathComponent("CollegeAppDebug.log")
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
        try? header.write(to: fileURL, atomically: true, encoding: .utf8)

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
        osLogger.debug("\(message, privacy: .public)")
        return
        #endif

        let now = Date()
        let ts = DebugLogger.formatTimestamp(now)
        let elapsed = String(format: "%.3fs", now.timeIntervalSince(startTime))
        let thread = Thread.isMainThread ? "main" : "bg"
        let fileName = file.split(separator: "/").last.map(String.init) ?? file

        let logMessage = "[\(ts) +\(elapsed)] [\(level.rawValue)] [\(category.rawValue)] [\(thread)] \(fileName):\(line) \(function) — \(message)\n"

        // Always emit to unified logging (respects system log levels).
        osLogger.debug("\(logMessage, privacy: .public)")

        #if DEBUG
        // Write to file on background queue for thread safety (debug-only).
        guard let fileURL = logFileURL else { return }
        queue.async { [fileURL] in
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                handle.seekToEndOfFile()
                if let data = logMessage.data(using: .utf8) {
                    handle.write(data)
                }
                try? handle.close()
            } else {
                try? logMessage.write(to: fileURL, atomically: true, encoding: .utf8)
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
        // Avoid sharing DateFormatter across threads (it's not thread-safe).
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone.current
        df.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return df.string(from: date)
    }
}
