#if os(macOS)
import AppKit
import Combine
import ObjectiveC
import SwiftUI

@MainActor
final class SettingsSessionController: NSObject, ObservableObject, NSToolbarDelegate {
    private let sidebarItemID = NSToolbarItem.Identifier("com.college.settings.sidebar")
    private let backItemID = NSToolbarItem.Identifier("com.college.settings.back")
    private let forwardItemID = NSToolbarItem.Identifier("com.college.settings.forward")
    private let toolbarIdentifier = NSToolbar.Identifier("com.college.settings-toolbar")

    private weak var window: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    @Published var selectedSection: SettingsNavSection = .general
    @Published var listSelection: SettingsNavSection? = .general
    @Published var history: [SettingsNavSection] = [.general]
    @Published var historyIndex: Int = 0
    @Published var isSidebarVisible: Bool = true

    private var isHistoryNavigation = false

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

    func toggleSidebar() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isSidebarVisible.toggle()
        }
    }

    func attachWindowIfNeeded(_ window: NSWindow) {
        if self.window === window, window.toolbar?.identifier == toolbarIdentifier {
            refreshChrome()
            return
        }

        self.window = window
        configureWindowChrome(window)

        let toolbar = NSToolbar(identifier: toolbarIdentifier)
        toolbar.delegate = self
        toolbar.displayMode = .default
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar

        bindButtonStates()
        refreshChrome()
    }

    func refreshChrome() {
        window?.title = selectedSection.rawValue
        setButtonEnabled(backItemID, enabled: canGoBack)
        setButtonEnabled(forwardItemID, enabled: canGoForward)
    }

    private func configureWindowChrome(_ window: NSWindow) {
        window.styleMask.insert(.fullSizeContentView)
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = false
        window.toolbarStyle = .unified
    }

    private func bindButtonStates() {
        cancellables.removeAll()
        Publishers.CombineLatest($historyIndex, $history)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in
                self?.refreshChrome()
            }
            .store(in: &cancellables)
    }

    private func setButtonEnabled(_ id: NSToolbarItem.Identifier, enabled: Bool) {
        guard let toolbar = window?.toolbar else { return }
        for item in toolbar.items where item.itemIdentifier == id {
            (item.view as? NSButton)?.isEnabled = enabled
        }
    }

    nonisolated func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        MainActor.assumeIsolated {
            [sidebarItemID, backItemID, forwardItemID, .flexibleSpace, .flexibleSpace]
        }
    }

    nonisolated func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        MainActor.assumeIsolated {
            [sidebarItemID, backItemID, forwardItemID, .flexibleSpace, .space]
        }
    }

    nonisolated func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        MainActor.assumeIsolated { makeItem(for: itemIdentifier) }
    }

    private func makeItem(for id: NSToolbarItem.Identifier) -> NSToolbarItem? {
        switch id {
        case sidebarItemID:
            return makeIconItem(id, symbol: "sidebar.leading", tip: "Toggle Sidebar") { [weak self] in
                self?.toggleSidebar()
            }
        case backItemID:
            let item = makeIconItem(id, symbol: "chevron.left", tip: "Back") { [weak self] in
                Task { @MainActor in self?.goBack() }
            }
            (item.view as? NSButton)?.isEnabled = canGoBack
            return item
        case forwardItemID:
            let item = makeIconItem(id, symbol: "chevron.right", tip: "Forward") { [weak self] in
                Task { @MainActor in self?.goForward() }
            }
            (item.view as? NSButton)?.isEnabled = canGoForward
            return item
        default:
            return nil
        }
    }

    private func makeIconItem(
        _ id: NSToolbarItem.Identifier,
        symbol: String,
        tip: String,
        action: @escaping () -> Void
    ) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: id)
        let button = NSButton(frame: .zero)
        button.bezelStyle = .texturedRounded
        button.isBordered = false
        let config = NSImage.SymbolConfiguration(scale: .medium)
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)?
            .withSymbolConfiguration(config)
        button.toolTip = tip
        let bridge = SettingsToolbarActionBridge(action: action)
        objc_setAssociatedObject(button, &SettingsToolbarActionBridge.key, bridge, .OBJC_ASSOCIATION_RETAIN)
        button.target = bridge
        button.action = #selector(SettingsToolbarActionBridge.invoke)
        item.view = button
        item.toolTip = tip
        return item
    }
}

private final class SettingsToolbarActionBridge: NSObject {
    nonisolated(unsafe) static var key: UInt8 = 0
    private let action: () -> Void
    init(action: @escaping () -> Void) { self.action = action }
    @objc func invoke() { action() }
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

#endif
