import Foundation

enum UncaughtExceptionLogger {
    private static let lock = NSLock()
    private nonisolated(unsafe) static var installed = false

    static func installIfNeeded() {
        lock.lock()
        defer { lock.unlock() }
        guard !installed else { return }
        installed = true

        NSSetUncaughtExceptionHandler { exception in
            let name = exception.name.rawValue
            let reason = exception.reason ?? "(no reason)"
            let symbols = exception.callStackSymbols.joined(separator: "\n")
            let summary = "Uncaught NSException: \(name)\nReason: \(reason)"

            NSLog("%@", summary)
            NSLog("%@", symbols)

            DebugLogger.shared.log(summary, category: .system, level: .error)
            DebugLogger.shared.log(symbols, category: .system, level: .error)
            CrashReportStore.recordUncaughtException(name: name, reason: reason, callStackSymbols: exception.callStackSymbols)

            #if DEBUG
            UnlockDebugLog.log(summary)
            UnlockDebugLog.log(symbols)
            #endif
        }
    }
}
