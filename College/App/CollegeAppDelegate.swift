// CollegeAppDelegate.swift
// Feature: App
// Purpose: App module — CollegeAppDelegate.
// Data: CollegePersistence / repositories when applicable.

import AppKit

/// Dock menu and Finder-open document delivery (`.portal` backups).
@MainActor
final class CollegeAppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaultsWindowAutosaveCleanup.runAtLaunch()
        installEarlyWindowChromeObserver()
        AppActivityCoordinator.shared.refreshPolicyFromSettings()
        UITestLaunchFlags.scheduleUITestActivationRetriesIfNeeded()
        Task(priority: .utility) {
            CatalogStoreCoordinator.shared.migrateUniversitiesFromCurrentStoreIfNeeded()
        }
        let backgroundReport = BackgroundTaskCompliance.evaluateFromMainBundle()
        if !backgroundReport.isConfigured {
            DebugLogger.shared.log("⚠️ Background task compliance warnings: \(backgroundReport.warnings.joined(separator: " | "))")
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        UITestLaunchFlags.activateMainWindowIfUITestBoot()
        AppActivityCoordinator.shared.appDidBecomeActive()
    }

    func applicationDidResignActive(_ notification: Notification) {
        AppActivityCoordinator.shared.appDidResignActive()
    }

    func applicationWillTerminate(_ notification: Notification) {
        SessionTerminationTracker.markCleanTermination()
    }

    // MARK: - Window chrome

    /// Registers a persistent observer that applies the full-size-content-view chrome
    /// whenever a resizable app window becomes key.
    ///
    /// Using a persistent (non-one-shot) observer is important: a one-shot approach fires
    /// for the *first* key notification which may be the Settings window (fixed-size,
    /// not resizable) rather than the main ContentView window, causing the observer to
    /// self-remove before the correct window is ever configured.
    ///
    /// Filtering on `styleMask.contains(.resizable)` restricts the chrome to the main
    /// resizable window and skips Settings, sheets, and panels.  `applyWindowChrome` is
    /// idempotent, so repeated calls on the same window are safe.
    private func installEarlyWindowChromeObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWindowDidBecomeKey(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
    }

    @objc
    private func handleWindowDidBecomeKey(_ note: Notification) {
        guard let window = note.object as? NSWindow,
              window.styleMask.contains(.resizable),
              !window.isSheet else { return }
        CollegeAppDelegate.applyWindowChrome(to: window)
    }

    /// Applies the unified-toolbar / full-size-content-view chrome to a window.
    /// Idempotent — safe to call multiple times.
    static func applyWindowChrome(to window: NSWindow) {
        let stableAutosave = AutosaveNames.mainWindow
        if window.frameAutosaveName != stableAutosave {
            window.setFrameAutosaveName(stableAutosave)
        }
        if !window.styleMask.contains(.fullSizeContentView) {
            window.styleMask.insert(.fullSizeContentView)
        }
        if !window.titlebarAppearsTransparent {
            window.titlebarAppearsTransparent = true
        }
        if !window.isMovableByWindowBackground {
            window.isMovableByWindowBackground = true
        }
        if window.toolbarStyle != .unified {
            window.toolbarStyle = .unified
        }
        // Leave `collectionBehavior` unset here so the green traffic light keeps Apple’s
        // system window-management UI (Move & Resize, Fill & Arrange, Full Screen).
        // Defer titleVisibility so it runs after SwiftUI's toolbar initialisation, which
        // can reset it back to .visible if we set it synchronously too early.
        //
        // UI tests: keep the title visible so the main `NSWindow` reliably exposes its
        // SwiftUI content in the accessibility tree (XCTest otherwise saw no `Window`).
        guard !UITestLaunchFlags.forcesMainUI else { return }
        guard window.titleVisibility != .hidden else { return }
        DispatchQueue.main.async { [weak window] in
            guard let window, window.titleVisibility != .hidden else { return }
            window.titleVisibility = .hidden
        }
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()

        func addPage(_ title: String, raw: String) {
            let item = NSMenuItem(title: title, action: #selector(openDockSection(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = raw
            menu.addItem(item)
        }

        addPage(String(localized: "app.page.overview"), raw: AppPage.degree.rawValue)
        addPage(String(localized: "app.page.academics"), raw: AppPage.academics.rawValue)
        addPage(String(localized: "app.page.calendar"), raw: AppPage.calendar.rawValue)
        addPage(AppPage.assistant.displayTitle, raw: AppPage.assistant.rawValue)
        addPage(LMSPortalConfiguration.sidebarDisplayTitle, raw: AppPage.brightspace.rawValue)
        addPage(String(localized: "app.page.documents"), raw: AppPage.documents.rawValue)
        addPage(String(localized: "app.page.profile"), raw: AppPage.profile.rawValue)

        for sc in WebShortcutStore.loadAllSync() {
            addPage(sc.title, raw: AppPage.webShortcutPage(id: sc.id).rawValue)
        }

        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(
            title: String(localized: "app.page.settings"),
            action: #selector(openDockSettings(_:)),
            keyEquivalent: ""
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        return menu
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            guard url.isFileURL else { continue }
            let ext = url.pathExtension.lowercased()
            if ext == "portal" {
                NotificationCenter.default.post(
                    name: .plannerImportPortalBackupFileURL,
                    object: nil,
                    userInfo: ["url": url]
                )
            } else if ext == CatalogBundle.fileExtension || (ext == "sqlite" && url.lastPathComponent.lowercased().hasSuffix(".collegecatalog.sqlite")) {
                NotificationCenter.default.post(
                    name: .plannerImportCatalogBundleFileURL,
                    object: nil,
                    userInfo: ["url": url]
                )
            }
        }
    }

    @objc private func openDockSection(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String else { return }
        NotificationCenter.default.post(
            name: .plannerOpenPage,
            object: nil,
            userInfo: ["pageRaw": raw]
        )
    }

    @objc private func openDockSettings(_ sender: Any?) {
        MacPreferencesWindow.show()
    }
}
