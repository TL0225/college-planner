// SessionTerminationTracker.swift
// Feature: App
// Purpose: App module — SessionTerminationTracker.
// Data: CollegePersistence / repositories when applicable.

import Foundation

/// Tracks whether the previous process exited via normal termination so the next launch can detect force quits / crashes.
enum SessionTerminationTracker {
    private static let lastExitWasCleanKey = "College.session.lastExitWasClean"

    /// Call once after the app is ready to show UI (e.g. preload finished). Returns `true` when the prior session did not exit cleanly.
    static func consumePendingAbruptTerminationPrompt() -> Bool {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: lastExitWasCleanKey) == nil {
            defaults.set(false, forKey: lastExitWasCleanKey)
            return false
        }
        let lastWasClean = defaults.bool(forKey: lastExitWasCleanKey)
        defaults.set(false, forKey: lastExitWasCleanKey)
        return !lastWasClean
    }

    static func markCleanTermination() {
        UserDefaults.standard.set(true, forKey: lastExitWasCleanKey)
    }
}
