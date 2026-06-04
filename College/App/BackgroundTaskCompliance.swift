// BackgroundTaskCompliance.swift
// Feature: App
// Purpose: App module — Report.
// Data: CollegePersistence / repositories when applicable.

import Foundation

enum BackgroundTaskCompliance {
    struct Report: Sendable {
        let isConfigured: Bool
        let warnings: [String]
    }

    static func evaluateFromMainBundle() -> Report {
        #if os(macOS)
        // Native macOS app primarily uses NSBackgroundActivityScheduler flows.
        // We still check plist declarations so configuration drift is visible early.
        #endif
        let info = Bundle.main.infoDictionary ?? [:]
        let permittedIDs = info["BGTaskSchedulerPermittedIdentifiers"] as? [String] ?? []
        let backgroundModes = info["UIBackgroundModes"] as? [String] ?? []

        var warnings: [String] = []
        if permittedIDs.isEmpty {
            warnings.append("BGTaskSchedulerPermittedIdentifiers is missing or empty.")
        }
        if backgroundModes.isEmpty {
            warnings.append("UIBackgroundModes is missing; background scheduling may be constrained.")
        }
        return Report(isConfigured: warnings.isEmpty, warnings: warnings)
    }
}
