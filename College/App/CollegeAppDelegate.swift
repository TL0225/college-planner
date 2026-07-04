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
        HostedUnitTestWindowPolicy.applyIfNeeded()
        installEarlyWindowChromeObserver()
        AppActivityCoordinator.shared.refreshPolicyFromSettings()
        UITestLaunchFlags.scheduleUITestActivationRetriesIfNeeded()
        Task { @MainActor in
            await BackgroundServiceRegistry.shared.bootstrap(phase: .atLaunch)
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
        final class TerminateDrain: @unchecked Sendable {
            var finished = false
        }
        let drain = TerminateDrain()
        Task { @MainActor in
            await BackgroundServiceRegistry.shared.stopAll()
            await DeGoogSidecarManager.shared.stopIfRunning()
            drain.finished = true
        }
        let deadline = Date().addingTimeInterval(2)
        while !drain.finished && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
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
        applyDeferredTitleVisibility(to: window)
    }

    /// macOS 26 (Tahoe): keep the AppKit title visible so the page name survives CMD+Tab.
    /// Hiding `titleVisibility` and relying on SwiftUI inline `navigationTitle` alone drops
    /// the label when the window loses key status on pages without a `.principal` toolbar item
    /// (Overview, Documents, …). Settings uses the same visible-title policy.
    ///
    /// Pre-26: hide the native title bar text; SwiftUI `navigationTitle` renders inline.
    private static func applyDeferredTitleVisibility(to window: NSWindow) {
        if #available(macOS 26.0, *) {
            guard window.titleVisibility != .visible else { return }
            DispatchQueue.main.async { [weak window] in
                guard let window, window.titleVisibility != .visible else { return }
                window.titleVisibility = .visible
            }
            return
        }
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
        if LMSPortalConfiguration.isLMSTabEnabled() {
            addPage(LMSPortalConfiguration.sidebarDisplayTitle, raw: AppPage.lms.rawValue)
        }
        addPage(String(localized: "app.page.documents"), raw: AppPage.documents.rawValue)
        addPage(String(localized: "app.page.profile"), raw: AppPage.profile.rawValue)

        for sc in WebShortcutStore.loadAllSync() {
            addPage(sc.title, raw: AppPage.webShortcutPage(id: sc.id).rawValue)
        }
        for group in WebShortcutStore.loadGroupsSync() {
            for sc in group.shortcuts {
                addPage("\(group.name) — \(sc.title)", raw: AppPage.webShortcutPage(id: sc.id).rawValue)
            }
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
                AppTypedNavigationRouter.importCatalogBundle(at: url)
            }
        }
    }

    @objc private func openDockSection(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let page = AppPage(rawValue: raw) else { return }
        AppTypedNavigationRouter.openPage(page)
    }

    @objc private func openDockSettings(_ sender: Any?) {
        MacPreferencesWindow.show()
    }
}

// MARK: - Hosted unit test window suppression

/// App-hosted unit tests (`CollegeTests` inside `College.app`) still create a SwiftUI
/// `WindowGroup`. Without this, users see a large empty gray window while tests run.
enum HostedUnitTestWindowPolicy {
    private static var shouldSuppress: Bool {
        CollegeTestRuntime.isUnitTestProcess && !UITestLaunchFlags.forcesMainUI
    }

    static func applyIfNeeded() {
        guard shouldSuppress else { return }
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                orderOutAllWindows()
            }
        }
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeMainNotification,
            object: nil,
            queue: .main
        ) { note in
            guard shouldSuppress else { return }
            let window = note.object as? NSWindow
            Task { @MainActor in
                window?.orderOut(nil)
            }
        }
    }

    @MainActor
    private static func orderOutAllWindows() {
        NSApp.windows.forEach { $0.orderOut(nil) }
    }
}
