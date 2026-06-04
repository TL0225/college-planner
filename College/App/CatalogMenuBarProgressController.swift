// CatalogMenuBarProgressController.swift
// Feature: App
// Purpose: App module — CatalogMenuBarProgressController.
// Data: CollegePersistence / repositories when applicable.

import AppKit

extension Notification.Name {
    static let collegeCatalogBackgroundImportClicked = Notification.Name("College.catalogBackgroundImportClicked")
}

/// Persistent menu bar item (app icon): click shows catalog import status and “Open College”.
@MainActor
final class CatalogMenuBarProgressController: NSObject, NSMenuDelegate {
    static let shared = CatalogMenuBarProgressController()

    private var statusItem: NSStatusItem?
    private lazy var catalogStatusMenu: NSMenu = {
        let m = NSMenu()
        m.delegate = self
        return m
    }()

    private var importTitle: String = ""
    private var importFraction: Double = 0
    private var importIndeterminate: Bool = false
    private var importCompletedCount: Int?
    private var importTotalCount: Int?
    private var importStage: String?
    private var isImporting: Bool = false
    private var isPurging: Bool = false
    private var purgeTitle: String = ""
    private var lastFinishedSummary: String?

    nonisolated(unsafe) private var observer: NSObjectProtocol?
    nonisolated(unsafe) private var purgeObserver: NSObjectProtocol?

    private override init() {
        super.init()
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
        if let purgeObserver {
            NotificationCenter.default.removeObserver(purgeObserver)
        }
    }

    func startObservingProgressNotifications() {
        guard observer == nil else {
            ensurePersistentStatusItem()
            return
        }
        observer = NotificationCenter.default.addObserver(
            forName: .collegeCatalogBackgroundImportProgress,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let finished = (note.userInfo?["finished"] as? Bool) == true
            let title = (note.userInfo?["title"] as? String) ?? ""
            let fraction = (note.userInfo?["fraction"] as? Double) ?? 0
            let indeterminate = (note.userInfo?["indeterminate"] as? Bool) == true
            let completedCount = note.userInfo?["completedCount"] as? Int
            let totalCount = note.userInfo?["totalCount"] as? Int
            let stage = note.userInfo?["stage"] as? String
            Task { @MainActor in
                self?.applyProgressPayload(
                    finished: finished,
                    title: title,
                    fraction: fraction,
                    indeterminate: indeterminate,
                    completedCount: completedCount,
                    totalCount: totalCount,
                    stage: stage
                )
            }
        }
        purgeObserver = NotificationCenter.default.addObserver(
            forName: .collegeCatalogScrapePurgeProgress,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let finished = (note.userInfo?["finished"] as? Bool) == true
            let failed = (note.userInfo?["failed"] as? Bool) == true
            let title = (note.userInfo?["title"] as? String) ?? ""
            let summary = (note.userInfo?["summary"] as? String) ?? title
            Task { @MainActor in
                self?.applyPurgePayload(finished: finished, failed: failed, title: title, summary: summary)
            }
        }
        ensurePersistentStatusItem()
    }

    private func applyPurgePayload(finished: Bool, failed: Bool, title: String, summary: String) {
        if finished {
            isPurging = false
            purgeTitle = ""
            lastFinishedSummary = failed
                ? String(localized: "menubar.catalog_purge.failed_generic", defaultValue: "Catalog reset did not finish cleanly.")
                : (summary.isEmpty
                    ? String(localized: "menubar.catalog_purge.succeeded_generic", defaultValue: "Catalog scrape data cleared.")
                    : summary)
            statusItem?.button?.toolTip = catalogMenuHeaderStatusText()
            return
        }
        isPurging = true
        purgeTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        statusItem?.button?.toolTip = catalogMenuHeaderStatusText()
    }

    private func applyProgressPayload(
        finished: Bool,
        title rawTitle: String,
        fraction: Double,
        indeterminate: Bool,
        completedCount: Int?,
        totalCount: Int?,
        stage: String?
    ) {
        let trimmedTitle = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)

        if finished {
            isImporting = false
            importTitle = ""
            importFraction = 0
            importIndeterminate = false
            importCompletedCount = nil
            importTotalCount = nil
            importStage = nil
            lastFinishedSummary = String(localized: "menubar.catalog.finished", defaultValue: "Last catalog import finished.")
            return
        }

        isImporting = true
        importTitle = trimmedTitle
        importFraction = fraction
        importIndeterminate = indeterminate
        if let completedCount {
            importCompletedCount = completedCount
        }
        if let totalCount {
            importTotalCount = totalCount
        }
        if let stage {
            importStage = stage
        }
    }

    private func ensurePersistentStatusItem() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        item.menu = catalogStatusMenu
        item.button?.image = NSImage(systemSymbolName: "graduationcap.fill", accessibilityDescription: "College")
        item.button?.toolTip = catalogMenuHeaderStatusText()
        rebuildMenu()
    }

    private func catalogMenuHeaderStatusText() -> String {
        if isPurging {
            if purgeTitle.isEmpty {
                return String(localized: "menubar.catalog_purge.in_progress", defaultValue: "Clearing catalog scrape data…")
            }
            return purgeTitle
        }
        if isImporting {
            if let completed = importCompletedCount,
               completed >= 0,
               let total = importTotalCount,
               total > 0 {
                let stageLabel = (importStage ?? "Progress").trimmingCharacters(in: .whitespacesAndNewlines)
                if importTitle.isEmpty {
                    return "\(stageLabel) \(completed) / \(total)"
                }
                return "\(stageLabel) \(completed) / \(total) — \(importTitle)"
            }
            if importIndeterminate || importFraction <= 0 || !importFraction.isFinite {
                return importTitle.isEmpty
                    ? String(localized: "menubar.catalog.menu.importing", defaultValue: "Catalog import in progress…")
                    : importTitle
            }
            return importTitle.isEmpty
                ? String(localized: "menubar.catalog.menu.importing", defaultValue: "Catalog import in progress…")
                : importTitle
        }
        if let last = lastFinishedSummary {
            return last
        }
        return String(localized: "menubar.catalog.menu.idle", defaultValue: "No catalog import running.")
    }

    func menuWillOpen(_ menu: NSMenu) {
        guard menu === catalogStatusMenu else { return }
        rebuildMenu()
    }

    private func rebuildMenu() {
        catalogStatusMenu.removeAllItems()
        let statusItem = NSMenuItem(title: catalogMenuHeaderStatusText(), action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        catalogStatusMenu.addItem(statusItem)
    }
}
