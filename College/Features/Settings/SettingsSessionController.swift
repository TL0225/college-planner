// SettingsSessionController.swift
// Feature: Settings
// Purpose: Settings module — section state, history, and lightweight window chrome.
// Data: CollegePersistence / repositories when applicable.
//
// The sidebar toggle and toolbar are owned entirely by SwiftUI's `NavigationSplitView`.
// This controller intentionally does NOT install a custom `NSToolbar` — having both a
// SwiftUI split-view toolbar and an AppKit toolbar caused the sidebar button to appear
// twice / jump sides between sections.

import AppKit
import Combine
import SwiftUI

@MainActor
final class SettingsSessionController: NSObject, ObservableObject {
    private weak var window: NSWindow?

    private static let lastSectionKey = "settings.lastSelectedSection"

    @Published var selectedSection: SettingsNavSection
    @Published var listSelection: SettingsNavSection?
    @Published var history: [SettingsNavSection]
    @Published var historyIndex: Int = 0
    @Published var isSidebarVisible: Bool = true

    private var isHistoryNavigation = false

    override init() {
        let initial: SettingsNavSection = .profile
        selectedSection = initial
        listSelection = initial
        history = [initial]
        super.init()
    }

    var canGoBack: Bool { historyIndex > 0 }
    var canGoForward: Bool { historyIndex < history.count - 1 }

    func selectSection(_ section: SettingsNavSection) {
        guard !isHistoryNavigation else { return }
        if section != selectedSection {
            history.removeLast(history.count - historyIndex - 1)
            history.append(section)
            historyIndex = history.count - 1
        }
        selectedSection = section
        listSelection = section
        UserDefaults.standard.set(section.rawValue, forKey: Self.lastSectionKey)
        refreshChrome()
    }

    func goBack() {
        guard canGoBack else { return }
        isHistoryNavigation = true
        historyIndex -= 1
        let section = history[historyIndex]
        selectedSection = section
        listSelection = section
        isHistoryNavigation = false
        refreshChrome()
    }

    func goForward() {
        guard canGoForward else { return }
        isHistoryNavigation = true
        historyIndex += 1
        let section = history[historyIndex]
        selectedSection = section
        listSelection = section
        isHistoryNavigation = false
        refreshChrome()
    }

    func attachWindowIfNeeded(_ window: NSWindow) {
        if self.window === window {
            refreshChrome()
            return
        }
        self.window = window
        configureWindowChrome(window)
        refreshChrome()
    }

    func refreshChrome() {
        window?.title = selectedSection.displayName
    }

    private func configureWindowChrome(_ window: NSWindow) {
        window.styleMask.insert(.fullSizeContentView)
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = false
        window.toolbarStyle = .unified
        hideStandardWindowButtons(in: window)
    }

    /// Settings is a single-pane window, so only the close (red) traffic light is meaningful.
    /// Remove the miniaturize (yellow) and zoom (green) dots entirely rather than dimming them.
    /// `.resizable` is kept so SwiftUI's automatic window sizing/layout still works.
    private func hideStandardWindowButtons(in window: NSWindow) {
        window.styleMask.remove(.miniaturizable)
        for role: NSWindow.ButtonType in [.miniaturizeButton, .zoomButton] {
            window.standardWindowButton(role)?.isHidden = true
        }
    }
}

struct SettingsWindowChromeAttacher: NSViewRepresentable {
    @ObservedObject var session: SettingsSessionController

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.isHidden = true
        DispatchQueue.main.async {
            if let window = view.window {
                session.attachWindowIfNeeded(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window {
                session.attachWindowIfNeeded(window)
            }
        }
        session.refreshChrome()
    }
}
