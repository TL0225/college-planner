// LaunchShellPagePersistence.swift
// Feature: App
// Purpose: App module — LaunchShellPagePersistence.
// Data: CollegePersistence / repositories when applicable.

import Foundation

/// Persists the last main shell page for optional restore at launch.
enum LaunchShellPagePersistence {
    private static let key = "College.launch.lastShellPage"

    static func record(_ page: AppPage) {
        UserDefaults.standard.set(page.rawValue, forKey: key)
    }

    static func restoredPage() -> AppPage? {
        guard let raw = UserDefaults.standard.string(forKey: key) else { return nil }
        return AppPage(rawValue: raw)
    }
}
