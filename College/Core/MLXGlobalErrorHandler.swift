// MLXGlobalErrorHandler.swift
// Feature: Core
// Purpose: Core module — MLXGlobalErrorHandler.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import MLX
import Cmlx
import os

/// Installs a process-wide MLX error handler so the C++/C layer never calls `fatalError` when
/// Swift `withError` task-locals are not active (e.g. work on helper threads).
enum MLXGlobalErrorHandler {
    private static let lock = NSLock()
    private nonisolated(unsafe) static var didInstall = false

    static func installIfNeeded() {
        lock.lock()
        defer { lock.unlock() }
        guard !didInstall else { return }
        didInstall = true

        mlx_set_error_handler(Self.cErrorHandler, nil, nil)
    }

    private static let cErrorHandler: @convention(c) (UnsafePointer<CChar>?, UnsafeMutableRawPointer?) -> Void = { cMessage, _ in
        let text = cMessage.map { String(cString: $0) } ?? "(unknown MLX error)"
        os_log("%{public}@", log: Self.log, type: .error, "MLX: \(text)")
        DebugLogger.shared.log(
            "MLX (global): \(text)",
            category: .system,
            level: .error
        )
    }

    private static let log = OSLog(subsystem: Bundle.main.bundleIdentifier ?? "College", category: "MLX")
}
