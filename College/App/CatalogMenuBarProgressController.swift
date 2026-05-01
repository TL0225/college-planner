#if os(macOS)
import AppKit

extension Notification.Name {
    /// Posted when a background catalog import updates progress (`userInfo`: `fraction` Double 0...1, `title` String, optional `finished` Bool, optional `indeterminate` Bool).
    static let collegeCatalogBackgroundImportProgress = Notification.Name("College.catalogBackgroundImportProgress")
}

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
    private var isImporting: Bool = false
    private var lastFinishedSummary: String?

    nonisolated(unsafe) private var observer: NSObjectProtocol?

    private override init() {
        super.init()
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
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
            Task { @MainActor in
                self?.applyProgressPayload(
                    finished: finished,
                    title: title,
                    fraction: fraction,
                    indeterminate: indeterminate
                )
            }
        }
        ensurePersistentStatusItem()
    }

    private func applyProgressPayload(finished: Bool, title rawTitle: String, fraction: Double, indeterminate: Bool) {
        let trimmedTitle = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)

        if finished {
            isImporting = false
            importTitle = ""
            importFraction = 0
            importIndeterminate = false
            lastFinishedSummary = String(localized: "menubar.catalog.finished", defaultValue: "Last catalog import finished.")
            return
        }

        isImporting = true
        importTitle = trimmedTitle
        importFraction = fraction
        importIndeterminate = indeterminate
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
        if isImporting {
            if importIndeterminate || importFraction <= 0 || !importFraction.isFinite {
                return importTitle.isEmpty
                    ? String(localized: "menubar.catalog.menu.importing", defaultValue: "Catalog import in progress…")
                    : importTitle
            }
            let pct = min(100, max(0, Int((importFraction * 100).rounded())))
            return importTitle.isEmpty
                ? String(format: String(localized: "menubar.catalog.menu.pct", defaultValue: "Importing catalog (%d%%)…"), pct)
                : "\(importTitle) (\(pct)%)"
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
#endif
