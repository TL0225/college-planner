// CollegeMenuBarStatusModel.swift
// Feature: App
// Purpose: App module — ProgressPayload.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import Observation

extension Notification.Name {
    /// Posted when a catalog import updates progress (`userInfo`: `fraction` Double, `title` String, optional `finished` Bool, optional `failed` Bool, optional `message`/`summary` String).
    static let collegeCatalogBackgroundImportProgress = Notification.Name("College.catalogBackgroundImportProgress")
}

/// Shared catalog / scrape status for the unified menu bar panel.
@Observable
@MainActor
final class CollegeMenuBarStatusModel {
    static let shared = CollegeMenuBarStatusModel()

    enum CatalogImportState: Equatable {
        case idle
        case inProgress(title: String, fraction: Double?, indeterminate: Bool)
        case succeeded(summary: String)
        case failed(message: String)
    }

    enum CatalogPurgeState: Equatable {
        case idle
        case inProgress(title: String, fraction: Double?, indeterminate: Bool)
        case succeeded(summary: String)
        case failed(message: String)
    }

    private(set) var catalog: CatalogImportState = .idle
    private(set) var catalogPurge: CatalogPurgeState = .idle

    nonisolated(unsafe) private var importObserver: NSObjectProtocol?
    nonisolated(unsafe) private var purgeObserver: NSObjectProtocol?

    private struct ProgressPayload: Sendable {
        let finished: Bool
        let failed: Bool
        let title: String
        let fraction: Double?
        let indeterminate: Bool
        let message: String?
        let summary: String?
        let completedCount: Int?
        let totalCount: Int?
        let stage: String?

        init(note: Notification) {
            let ui = note.userInfo ?? [:]
            finished = (ui["finished"] as? Bool) == true
            failed = (ui["failed"] as? Bool) == true
            title = (ui["title"] as? String) ?? ""
            fraction = ui["fraction"] as? Double
            indeterminate = (ui["indeterminate"] as? Bool) == true
            message = ui["message"] as? String
            summary = ui["summary"] as? String
            completedCount = ui["completedCount"] as? Int
            totalCount = ui["totalCount"] as? Int
            stage = ui["stage"] as? String
        }
    }

    private init() {}

    nonisolated deinit {
        MainActor.assumeIsolated {
            if let importObserver {
                NotificationCenter.default.removeObserver(importObserver)
            }
            if let purgeObserver {
                NotificationCenter.default.removeObserver(purgeObserver)
            }
        }
    }

    func startObservingProgressNotifications() {
        guard importObserver == nil else { return }
        importObserver = NotificationCenter.default.addObserver(
            forName: .collegeCatalogBackgroundImportProgress,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let payload = ProgressPayload(note: note)
            Task { @MainActor in
                self?.applyImport(payload)
            }
        }
        purgeObserver = NotificationCenter.default.addObserver(
            forName: .collegeCatalogScrapePurgeProgress,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let payload = PurgePayload(note: note)
            Task { @MainActor in
                self?.applyPurge(payload)
            }
        }
        if UserDefaults.standard.bool(forKey: OnboardingPreferenceBridge.catalogSyncInFlightKey) {
            catalog = .inProgress(
                title: String(
                    localized: "menubar.catalog.resuming",
                    defaultValue: "Catalog import in progress…"
                ),
                fraction: nil,
                indeterminate: true
            )
        }
    }

    private struct PurgePayload: Sendable {
        let finished: Bool
        let failed: Bool
        let title: String
        let fraction: Double?
        let indeterminate: Bool
        let message: String?
        let summary: String?
        let completedCount: Int?
        let totalCount: Int?
        let stage: String?

        init(note: Notification) {
            let ui = note.userInfo ?? [:]
            finished = (ui["finished"] as? Bool) == true
            failed = (ui["failed"] as? Bool) == true
            title = (ui["title"] as? String) ?? ""
            fraction = ui["fraction"] as? Double
            indeterminate = (ui["indeterminate"] as? Bool) == true
            message = ui["message"] as? String
            summary = ui["summary"] as? String
            completedCount = ui["completedCount"] as? Int
            totalCount = ui["totalCount"] as? Int
            stage = ui["stage"] as? String
        }
    }

    private func applyImport(_ payload: ProgressPayload) {
        if payload.finished {
            if payload.failed {
                let message = payload.message?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                catalog = .failed(
                    message: message?.isEmpty == false
                        ? message!
                        : String(
                            localized: "menubar.catalog.failed_generic",
                            defaultValue: "Catalog import failed."
                        )
                )
            } else {
                let summary = payload.summary?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                catalog = .succeeded(
                    summary: summary?.isEmpty == false
                        ? summary!
                        : String(
                            localized: "menubar.catalog.succeeded_generic",
                            defaultValue: "Catalog import finished."
                        )
                )
            }
            return
        }

        let title = payload.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalTitle: String
        if let completed = payload.completedCount,
           completed >= 0,
           let total = payload.totalCount,
           total > 0 {
            let stage = payload.stage?.trimmingCharacters(in: .whitespacesAndNewlines)
            let stagePrefix = (stage?.isEmpty == false) ? "\(stage!) \(completed) / \(total)" : "\(completed) / \(total)"
            finalTitle = title.isEmpty ? stagePrefix : "\(stagePrefix) — \(title)"
        } else {
            finalTitle = title
        }
        catalog = .inProgress(
            title: finalTitle.isEmpty
                ? String(
                    localized: "menubar.catalog.importing",
                    defaultValue: "Catalog import in progress…"
                )
                : finalTitle,
            fraction: payload.fraction,
            indeterminate: payload.indeterminate
        )
    }

    private func applyPurge(_ payload: PurgePayload) {
        if payload.finished {
            if payload.failed {
                let message = payload.message?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                catalogPurge = .failed(
                    message: message?.isEmpty == false
                        ? message!
                        : String(
                            localized: "menubar.catalog_purge.failed_generic",
                            defaultValue: "Catalog reset did not finish cleanly."
                        )
                )
            } else {
                let summary = payload.summary?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                catalogPurge = .succeeded(
                    summary: summary?.isEmpty == false
                        ? summary!
                        : String(
                            localized: "menubar.catalog_purge.succeeded_generic",
                            defaultValue: "Catalog scrape data cleared."
                        )
                )
            }
            return
        }

        let title = payload.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalTitle: String
        if let completed = payload.completedCount,
           completed >= 0,
           let total = payload.totalCount,
           total > 0 {
            let stage = payload.stage?.trimmingCharacters(in: .whitespacesAndNewlines)
            let stagePrefix = (stage?.isEmpty == false) ? "\(stage!) \(completed) / \(total)" : "\(completed) / \(total)"
            finalTitle = title.isEmpty ? stagePrefix : "\(stagePrefix) — \(title)"
        } else {
            finalTitle = title
        }
        catalogPurge = .inProgress(
            title: finalTitle.isEmpty
                ? String(
                    localized: "menubar.catalog_purge.in_progress",
                    defaultValue: "Clearing catalog scrape data…"
                )
                : finalTitle,
            fraction: payload.fraction,
            indeterminate: payload.indeterminate
        )
    }

    var isCatalogPurgeRunning: Bool {
        if case .inProgress = catalogPurge { return true }
        return false
    }

    var isCatalogImporting: Bool {
        if case .inProgress = catalog { return true }
        return false
    }

    var menuBarTooltip: String {
        if isCatalogPurgeRunning, case .inProgress(let title, _, _) = catalogPurge {
            return title
        }
        switch catalog {
        case .idle:
            return String(localized: "menubar.tooltip.idle", defaultValue: "College")
        case .inProgress(let title, let fraction, let indeterminate):
            if indeterminate || fraction == nil || fraction! <= 0 || !fraction!.isFinite {
                return title
            }
            return title
        case .succeeded(let summary):
            return summary
        case .failed(let message):
            return message
        }
    }

    var statusLine: String {
        switch catalog {
        case .idle:
            return String(
                localized: "menubar.status.idle",
                defaultValue: "No catalog import running."
            )
        case .inProgress(let title, let fraction, let indeterminate):
            if indeterminate || fraction == nil || fraction! <= 0 || !fraction!.isFinite {
                return title
            }
            return title
        case .succeeded(let summary):
            return summary
        case .failed(let message):
            return message
        }
    }

    var catalogProgressFraction: Double? {
        guard case .inProgress(_, let fraction, let indeterminate) = catalog,
              !indeterminate,
              let fraction,
              fraction > 0,
              fraction.isFinite
        else { return nil }
        return min(1, max(0, fraction))
    }
}
