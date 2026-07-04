// DiagnosticsSession.swift
// Feature: Debug
// Purpose: Per-launch session and operation correlation IDs for the event store.

import Foundation

enum DiagnosticsSession {
    /// One UUID per app launch; ties events to a single run and unified crash records.
    static let sessionID: String = UUID().uuidString

    private static let lock = NSLock()
    nonisolated(unsafe) private static var _currentCorrelationID: String?

    static func beginCorrelation(prefix: String = "op") -> String {
        let id = "\(prefix)_\(UUID().uuidString.prefix(8))"
        lock.lock()
        _currentCorrelationID = id
        lock.unlock()
        return id
    }

    static func currentCorrelationID() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return _currentCorrelationID
    }

    static func endCorrelation() {
        lock.lock()
        _currentCorrelationID = nil
        lock.unlock()
    }

    static func correlationID(orNew prefix: String = "op") -> String {
        if let existing = currentCorrelationID() { return existing }
        return beginCorrelation(prefix: prefix)
    }
}
