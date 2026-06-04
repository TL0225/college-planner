// AppToolbarCoordinator.swift
// Feature: App
// Purpose: App module — CalendarToolbarSearchMatch.
// Data: CollegePersistence / repositories when applicable.

import AppKit
import SwiftUI
import Observation

struct CalendarToolbarSearchMatch: Identifiable, Hashable, Sendable {
    let id: UUID
    let title: String
    let subtitle: String
}

// MARK: - AppToolbarCoordinator

/// Owns the macOS window toolbar via AppKit's NSToolbarDelegate.
///
/// Replacing SwiftUI `.toolbar { }` with a direct NSToolbar removes the
/// NavigationSplitView column-attribution bug that caused titles and toolbar
/// items to appear in the wrong position after navigation.
///
/// Architecture:
///   - ContentView creates this as @State and injects it via `.environment`.
///   - Per-page views (CalendarViewContent, BrightspaceView) receive it via
///     `@Environment(AppToolbarCoordinator.self)` and push live state updates (date strings, loading flags, etc.).
///   - Action callbacks flow back through onCalPrev / onBsBack / onNavigate etc.
@Observable
@MainActor
final class AppToolbarCoordinator: NSObject {

    // MARK: - Published State (read by NSHostingView toolbar subviews)

    var activePage: AppPage = .degree
    var calHeaderDate: String = ""
    var calViewMode: CalendarViewDisplayMode = .month
    var calSidebarShown: Bool = true
    var academicsSidebarShown: Bool = true
    var calSidebarPanel: CalendarSidebarPanel = .eventList
    var bsTitle: String = "Brightspace"
    var bsCanGoBack: Bool = false
    var bsCanGoForward: Bool = false
    var bsIsLoading: Bool = false
    var profileInitials: String = ""
    var searchText: String = ""
    var isExporting: Bool = false
    var calendarToolbarSearchText: String = ""
    var calendarToolbarSearchResults: [CalendarToolbarSearchMatch] = []
    var calendarToolbarSearchExpanded: Bool = false
    var assistantCanRegenerate: Bool = false
    /// When the primary `NavigationSplitView` sidebar is hidden (detail-only), the main nav sidebar toggle moves into the ``NSToolbar``; when the sidebar column is visible, it is drawn inside ``SidebarView`` instead.
    var showsMainNavSidebarToggleInToolbar: Bool = false

    // MARK: - Action Callbacks (wired by ContentView / page views)

    var onCalPrev: (() -> Void)?
    var onCalNext: (() -> Void)?
    var onCalModeChange: ((CalendarViewDisplayMode) -> Void)?
    var onCalSidebarToggle: (() -> Void)?
    var onCalSidebarPanelChange: ((CalendarSidebarPanel) -> Void)?
    var onBsBack: (() -> Void)?
    var onBsForward: (() -> Void)?
    var onBsReload: (() -> Void)?
    /// Jump to the configured Brightspace portal (startup URL), distinct from reload current page.
    var onBsPortalHome: (() -> Void)?
    var onBsFind: (() -> Void)?
    var onFilter: (() -> Void)?
    var onExport: (() -> Void)?
    var onAddSemester: (() -> Void)?
    var onAddCourse: (() -> Void)?
    var onAdvisorPrep: (() -> Void)?
    var onAssistantLibrary: (() -> Void)?
    var onAssistantRegenerate: (() -> Void)?
    /// Fired whenever the main sidebar toggle button is pressed (from toolbar or sidebar header host).
    /// ContentView uses this to keep `NavigationSplitView(columnVisibility:)` in sync with native AppKit actions.
    var onMainSidebarToggleRequested: (() -> Void)?
    /// Fires when a toolbar button wants to navigate to a page.
    /// ContentView sets activePageRaw in response, which triggers pageDidChange.
    var onNavigate: ((AppPage) -> Void)?

    // MARK: - Private

    private weak var window: NSWindow?
    private var observationTask: Task<Void, Never>?
    private var lastShowsMainNavSidebarToggleInToolbar = false
    private var lastAppliedWindowTitle: String?
    private var toolbarItemCache: [NSToolbarItem.Identifier: NSToolbarItem] = [:]

    // Retained so @ObservedObject inside each NSHostingView keeps receiving updates
    private var calChromeHost: NSHostingView<CalToolbarChromeView>?
    private var bsTitleHost: NSHostingView<BsToolbarTitleView>?
    private var profileHost: NSHostingView<ToolbarProfileAvatarView>?

    // MARK: - Identifiers

    /// Calendar center: prev/date/next and Month/Week/Day (between two `.flexibleSpace` items).
    let calChromeID = NSToolbarItem.Identifier("college.cal.chrome")
    /// Trailing sidebar toggle — separate item so it stays pinned to the toolbar’s trailing edge.
    let calSidebarToggleID = NSToolbarItem.Identifier("college.cal.sidebarToggle")
    let academicsSidebarToggleID = NSToolbarItem.Identifier("college.academics.sidebarToggle")
    let bsBackID     = NSToolbarItem.Identifier("college.bs.back")
    let bsForwardID  = NSToolbarItem.Identifier("college.bs.forward")
    let bsReloadID   = NSToolbarItem.Identifier("college.bs.reload")
    let bsTitleID    = NSToolbarItem.Identifier("college.bs.title")
    let filterID     = NSToolbarItem.Identifier("college.filter")
    let exportID     = NSToolbarItem.Identifier("college.export")
    let addID        = NSToolbarItem.Identifier("college.add")
    let searchID     = NSToolbarItem.Identifier("college.search")
    let magnifyID       = NSToolbarItem.Identifier("college.magnify")
    let sparklesID       = NSToolbarItem.Identifier("college.sparkles")
    let bellID           = NSToolbarItem.Identifier("college.bell")
    let profileID        = NSToolbarItem.Identifier("college.profile")
    let advisorPrepID    = NSToolbarItem.Identifier("college.profile.advisorPrep")
    let profileSettingsID = NSToolbarItem.Identifier("college.profile.settings")
    let assistantLibraryID = NSToolbarItem.Identifier("college.assistant.library")
    let assistantRegenerateID = NSToolbarItem.Identifier("college.assistant.regenerate")
    /// Leading column sidebar control. Do not use `NSToolbarItem.Identifier.toggleSidebar` for the hosted control:
    /// unified toolbars relocate that identifier’s item into the trailing cluster regardless of `itemIdentifiers` order.
    let mainLeadingSidebarToggleID = NSToolbarItem.Identifier("college.shell.mainLeadingSidebarToggle")

    // MARK: - Setup

    func attach(to window: NSWindow) {
          if let previousWindow = self.window,
              previousWindow !== window,
              let previousToolbar = previousWindow.toolbar,
              previousToolbar.delegate === self {
                previousToolbar.delegate = nil
          }

        if self.window === window,
           let existing = window.toolbar,
              existing.identifier == "com.college.main-toolbar",
           existing.delegate === self {
            return
        }

        self.window = window
                lastAppliedWindowTitle = nil
                toolbarItemCache.removeAll()
                calChromeHost = nil
                bsTitleHost = nil
                profileHost = nil
        if let existing = window.toolbar,
              existing.identifier == "com.college.main-toolbar",
           existing.delegate === self {
            bindObservationTracking()
            rebuildItems()
            return
        }

        if let existingToolbar = window.toolbar {
            // Reuse the AppKit toolbar instance so SwiftUI/AppKit observer bridges
            // tied to this toolbar are not orphaned by replacement.
            existingToolbar.delegate = self
            existingToolbar.displayMode = .iconOnly
            existingToolbar.allowsUserCustomization = false
        } else {
            let toolbar = NSToolbar(identifier: "com.college.main-toolbar")
            toolbar.delegate = self
            toolbar.displayMode = .iconOnly
            toolbar.allowsUserCustomization = false
            window.toolbar = toolbar
        }
        bindObservationTracking()
        rebuildItems()
    }

    /// Call whenever `SceneStorage` active page changes.
    func pageDidChange(_ page: AppPage) {
        applyPortalPage(page)
    }

    /// Sync window title and toolbar with the portal page. Call from `onAppear` too — `onChange` may not run for the initial value.
    func applyPortalPage(_ page: AppPage) {
        let changed = activePage != page
        activePage = page
        if changed {
            searchText = ""
            calendarToolbarSearchText = ""
            calendarToolbarSearchResults = []
            calendarToolbarSearchExpanded = false
        }
        applyWindowChromeIfNeeded()
        guard window?.toolbar != nil else { return }
        if changed {
            rebuildItems()
        }
    }

    // MARK: - Reactive Updates via Observation

    private func bindObservationTracking() {
        observationTask?.cancel()
        observationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            self.syncToolbarFromObservedState()
            while !Task.isCancelled {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    withObservationTracking {
                        _ = self.bsCanGoBack
                        _ = self.bsCanGoForward
                        _ = self.bsIsLoading
                        _ = self.isExporting
                        _ = self.assistantCanRegenerate
                        _ = self.showsMainNavSidebarToggleInToolbar
                    } onChange: {
                        continuation.resume()
                    }
                }
                guard !Task.isCancelled else { break }
                self.syncToolbarFromObservedState()
            }
        }
    }

    private func syncToolbarFromObservedState() {
        setButtonEnabled(id: bsBackID, enabled: bsCanGoBack)
        setButtonEnabled(id: bsForwardID, enabled: bsCanGoForward)
        setButtonEnabled(id: bsReloadID, enabled: !bsIsLoading)
        setButtonEnabled(id: exportID, enabled: !isExporting)
        setButtonEnabled(id: assistantRegenerateID, enabled: assistantCanRegenerate)
        if showsMainNavSidebarToggleInToolbar != lastShowsMainNavSidebarToggleInToolbar {
            lastShowsMainNavSidebarToggleInToolbar = showsMainNavSidebarToggleInToolbar
            rebuildItems()
        }
    }

    // MARK: - Toolbar Rebuild

    func rebuildItems() {
        guard let toolbar = window?.toolbar else { return }
        applyWindowChromeIfNeeded()
        
        // Pin the Calendar header chrome exactly to the center, otherwise reset to normal
        if activePage == .calendar {
            toolbar.centeredItemIdentifier = calChromeID
        } else {
            toolbar.centeredItemIdentifier = nil
        }
        
        let desired = identifiers(for: activePage)
        if toolbar.itemIdentifiers != desired {
            toolbar.itemIdentifiers = desired
            toolbar.validateVisibleItems()
        }
    }

    private func applyWindowChromeIfNeeded() {
        guard let window else { return }
        let nextTitle = activePage.windowChromeTitle
        if lastAppliedWindowTitle != nextTitle {
            window.title = nextTitle
            lastAppliedWindowTitle = nextTitle
        }
        if window.titleVisibility != .hidden {
            window.titleVisibility = .hidden
        }
    }

    /// Leading toolbar segment: custom sidebar toggle (`mainLeadingSidebarToggleID`) immediately followed by the HIG **`sidebarTrackingSeparator`**
    /// (`toggleSidebar` is not used—the system relocates it in unified chrome).
    private func mainNavSidebarPrefixToolbarItems() -> [NSToolbarItem.Identifier] {
        if showsMainNavSidebarToggleInToolbar {
            [mainLeadingSidebarToggleID, .sidebarTrackingSeparator, .flexibleSpace]
        } else {
            [.flexibleSpace]
        }
    }

    private func identifiers(for page: AppPage) -> [NSToolbarItem.Identifier] {
        let utilityItems = trailingUtilityIdentifiers()
        switch page {
        case .calendar:
            // Two flexible spaces center `calChrome`; inspector toggle follows HIG tracking separator.
            return mainNavSidebarPrefixToolbarItems() + [
                calChromeID,
                .flexibleSpace,
                .inspectorTrackingSeparator,
                calSidebarToggleID,
            ] + utilityItems
        case .brightspace:
            // Keep Brightspace chrome minimal in the window toolbar.
            return mainNavSidebarPrefixToolbarItems() + utilityItems
        case .degree:
            return mainNavSidebarPrefixToolbarItems() + utilityItems
        case .academics:
            return mainNavSidebarPrefixToolbarItems() + [
                addID,
                academicsSidebarToggleID,
            ] + utilityItems
        case .documents:
            return mainNavSidebarPrefixToolbarItems() + utilityItems
        case .assistant:
            return mainNavSidebarPrefixToolbarItems() + utilityItems
        case .profile:
            return mainNavSidebarPrefixToolbarItems() + utilityItems
        default:
            return mainNavSidebarPrefixToolbarItems() + utilityItems
        }
    }

    private func trailingUtilityIdentifiers() -> [NSToolbarItem.Identifier] {
        []
    }

    // MARK: - In-Place Update Helpers

    private func setButtonEnabled(id: NSToolbarItem.Identifier?, enabled: Bool) {
        guard let id, let toolbar = window?.toolbar else { return }
        for item in toolbar.items where item.itemIdentifier == id {
            (item.view as? NSButton)?.isEnabled = enabled
        }
    }

    // MARK: - @objc actions for menus (must be on self for NSMenuItem.target)

    @objc func addSemesterAction()     { onAddSemester?() }
    @objc func addCourseAction()       { onAddCourse?() }
    
    // MARK: - Sidebar Toggles
    var onAcademicsSidebarToggle: (() -> Void)?
}

// MARK: - NSToolbarDelegate

extension AppToolbarCoordinator: NSToolbarDelegate {

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        identifiers(for: activePage)
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        var ids = identifiers(for: activePage)
        if !ids.contains(mainLeadingSidebarToggleID) {
            ids.append(mainLeadingSidebarToggleID)
        }
        if !ids.contains(.sidebarTrackingSeparator) {
            ids.append(.sidebarTrackingSeparator)
        }
        if !ids.contains(.inspectorTrackingSeparator) {
            ids.append(.inspectorTrackingSeparator)
        }
        return ids + [.flexibleSpace, .space]
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        makeItem(for: itemIdentifier)
    }
}

// MARK: - Item Factory

private extension AppToolbarCoordinator {

    func makeItem(for id: NSToolbarItem.Identifier) -> NSToolbarItem? {
        if let cached = toolbarItemCache[id] {
            refreshDynamicState(for: cached, id: id)
            return cached
        }

        guard let created = makeNewItem(for: id) else {
            return nil
        }
        toolbarItemCache[id] = created
        refreshDynamicState(for: created, id: id)
        return created
    }

    func makeNewItem(for id: NSToolbarItem.Identifier) -> NSToolbarItem? {
        switch id {

        // ── Main Sidebar (leading, custom ID — avoids unified-toolbar relocation of `.toggleSidebar`) ──
        case mainLeadingSidebarToggleID:
            let item = NSToolbarItem(itemIdentifier: id)
            let host = NSHostingView(rootView: SafeSidebarToggleView {
                self.onMainSidebarToggleRequested?()
            })
            host.sizingOptions = [.preferredContentSize]
            host.translatesAutoresizingMaskIntoConstraints = true
            host.frame = CGRect(x: 0, y: 0, width: 32, height: 32)
            item.view = host
            item.isNavigational = true
            return item

        case .sidebarTrackingSeparator:
            return NSTrackingSeparatorToolbarItem(itemIdentifier: .sidebarTrackingSeparator)

        case .inspectorTrackingSeparator:
            return NSTrackingSeparatorToolbarItem(itemIdentifier: .inspectorTrackingSeparator)

        // ── Calendar ─────────────────────────────────────────────────────────
        case calChromeID:
            let item = NSToolbarItem(itemIdentifier: id)
            let host = NSHostingView(rootView: CalToolbarChromeView(coordinator: self))
            host.sizingOptions = [.preferredContentSize]
            host.translatesAutoresizingMaskIntoConstraints = true
            host.frame = CGRect(x: 0, y: 0, width: 400, height: 32)
            calChromeHost = host
            item.view = host
            return item

        case calSidebarToggleID:
            let item = NSToolbarItem(itemIdentifier: id)
            let host = NSHostingView(rootView: CalToolbarSidebarToggleView(coordinator: self))
            host.sizingOptions = [.preferredContentSize]
            host.translatesAutoresizingMaskIntoConstraints = true
            host.frame = CGRect(x: 0, y: 0, width: 32, height: 32)
            item.view = host
            return item
            
        // ── Academics ────────────────────────────────────────────────────────
        case academicsSidebarToggleID:
            let item = NSToolbarItem(itemIdentifier: id)
            let host = NSHostingView(rootView: AcademicsToolbarSidebarToggleView(coordinator: self))
            host.sizingOptions = [.preferredContentSize]
            host.translatesAutoresizingMaskIntoConstraints = true
            host.frame = CGRect(x: 0, y: 0, width: 32, height: 32)
            item.view = host
            return item

        // ── Brightspace ───────────────────────────────────────────────────────
        case bsBackID:
            let i = iconItem(id, symbol: "chevron.left", tip: "Back") { [weak self] in self?.onBsBack?() }
            (i.view as? NSButton)?.isEnabled = bsCanGoBack
            return i

        case bsForwardID:
            let i = iconItem(id, symbol: "chevron.right", tip: "Forward") { [weak self] in self?.onBsForward?() }
            (i.view as? NSButton)?.isEnabled = bsCanGoForward
            return i

        case bsReloadID:
            let item = iconItem(id, symbol: "arrow.clockwise", tip: "Reload") { [weak self] in self?.onBsReload?() }
            (item.view as? NSButton)?.isEnabled = !bsIsLoading
            return item

        case bsTitleID:
            let item = NSToolbarItem(itemIdentifier: id)
            let host = NSHostingView(rootView: BsToolbarTitleView(coordinator: self))
            host.translatesAutoresizingMaskIntoConstraints = true
            host.sizingOptions = [.preferredContentSize]
            host.frame = CGRect(x: 0, y: 0, width: 340, height: 32)
            bsTitleHost = host
            item.view = host
            return item

        // ── Shell pages ───────────────────────────────────────────────────────
        case filterID:
            return iconItem(
                id,
                symbol: "line.3.horizontal.decrease",
                tip: String(localized: "shell.toolbar.filter_help")
            ) { [weak self] in self?.onFilter?() }

        case exportID:
            let i = iconItem(
                id,
                symbol: "square.and.arrow.up",
                tip: String(localized: "shell.toolbar.export_help")
            ) { [weak self] in self?.onExport?() }
            (i.view as? NSButton)?.isEnabled = !isExporting
            return i

        case addID:
            return makeAddItem(id)

        case searchID:
            let searchItem = NSSearchToolbarItem(itemIdentifier: id)
            searchItem.searchField.placeholderString = String(localized: "overview.toolbar.search_courses")
            let bridge = ActionBridge { [weak self, weak searchItem] in
                self?.searchText = searchItem?.searchField.stringValue ?? ""
            }
            objc_setAssociatedObject(searchItem.searchField, &ActionBridge.key, bridge, .OBJC_ASSOCIATION_RETAIN)
            searchItem.searchField.target = bridge
            searchItem.searchField.action = #selector(ActionBridge.invoke)
            return searchItem

        case assistantLibraryID:
            return iconItem(id, symbol: "books.vertical", tip: "Saved web notes") { [weak self] in
                self?.onAssistantLibrary?()
            }

        case assistantRegenerateID:
            let item = iconItem(id, symbol: "arrow.clockwise", tip: "Regenerate last reply") { [weak self] in
                self?.onAssistantRegenerate?()
            }
            (item.view as? NSButton)?.isEnabled = assistantCanRegenerate
            return item

        // ── Common right-side icons ────────────────────────────────────────────
        case advisorPrepID:
            return iconItem(
                id,
                symbol: "doc.richtext",
                tip: String(localized: "profile.toolbar.advisor_prep")
            ) { [weak self] in self?.onAdvisorPrep?() }

        case profileSettingsID:
            return iconItem(
                id,
                symbol: "gearshape",
                tip: String(localized: "profile.toolbar.settings")
            ) {
                MacPreferencesWindow.show()
            }

        case magnifyID:
            return iconItem(
                id,
                symbol: "magnifyingglass",
                tip: String(localized: "brightspace.toolbar.find_in_page_help")
            ) { [weak self] in self?.onBsFind?() }

        case sparklesID:
            return iconItem(id, symbol: "sparkles", tip: "AI Assistant") { [weak self] in
                self?.onNavigate?(.assistant)
            }

        case bellID:
            return iconItem(id, symbol: "bell", tip: "Notifications") {}

        case profileID:
            let item = NSToolbarItem(itemIdentifier: id)
            let host = NSHostingView(rootView: ToolbarProfileAvatarView(coordinator: self))
            host.translatesAutoresizingMaskIntoConstraints = true
            host.frame = CGRect(x: 0, y: 0, width: 28, height: 28)
            profileHost = host
            item.view = host
            return item

        default:
            return nil
        }
    }

    func refreshDynamicState(for item: NSToolbarItem, id: NSToolbarItem.Identifier) {
        switch id {
        case bsBackID:
            (item.view as? NSButton)?.isEnabled = bsCanGoBack
        case bsForwardID:
            (item.view as? NSButton)?.isEnabled = bsCanGoForward
        case bsReloadID:
            (item.view as? NSButton)?.isEnabled = !bsIsLoading
        case exportID:
            (item.view as? NSButton)?.isEnabled = !isExporting
        case searchID:
            (item as? NSSearchToolbarItem)?.searchField.stringValue = searchText
        case assistantRegenerateID:
            (item.view as? NSButton)?.isEnabled = assistantCanRegenerate
        default:
            break
        }
    }

    // MARK: Icon button factory

    func iconItem(
        _ id: NSToolbarItem.Identifier,
        symbol: String,
        tip: String,
        action: @escaping () -> Void
    ) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: id)
        let button = NSButton(frame: .zero)
        button.bezelStyle = .regularSquare
        button.isBordered = false
        let config = NSImage.SymbolConfiguration(scale: .medium)
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)?
            .withSymbolConfiguration(config)
        button.toolTip = tip
        let bridge = ActionBridge(action: action)
        objc_setAssociatedObject(button, &ActionBridge.key, bridge, .OBJC_ASSOCIATION_RETAIN)
        button.target = bridge
        button.action = #selector(ActionBridge.invoke)
        button.setAccessibilityIdentifier("toolbar.\(id.rawValue)")
        item.view = button
        item.toolTip = tip
        item.isBordered = false
        return item
    }

    // MARK: Add menu item factory

    func makeAddItem(_ id: NSToolbarItem.Identifier) -> NSToolbarItem {
        let item = NSMenuToolbarItem(itemIdentifier: id)
        let menu = NSMenu()

        let semItem = NSMenuItem(
            title: String(localized: "shell.menu.add_semester"),
            action: #selector(addSemesterAction),
            keyEquivalent: ""
        )
        semItem.target = self
        menu.addItem(semItem)

        let courseItem = NSMenuItem(
            title: String(localized: "shell.menu.add_course"),
            action: #selector(addCourseAction),
            keyEquivalent: ""
        )
        courseItem.target = self
        menu.addItem(courseItem)

        item.menu = menu
        let config = NSImage.SymbolConfiguration(scale: .medium)
        item.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "Add")?
            .withSymbolConfiguration(config)
        item.showsIndicator = true
        item.isBordered = false
        return item
    }

}

// MARK: - Action Bridge (closure → target/action for AppKit buttons)

private final class ActionBridge: NSObject {
    nonisolated(unsafe) static var key: UInt8 = 0
    private let action: () -> Void
    init(action: @escaping () -> Void) { self.action = action }
    @objc func invoke() { action() }
}

// MARK: - SwiftUI Subviews hosted inside NSToolbarItems

/// Calendar toolbar center: < Month Year > and Month/Week/Day (toolbar item sits between two flexible spaces).
struct CalToolbarChromeView: View {
    var coordinator: AppToolbarCoordinator

    private var modeBinding: Binding<CalendarViewDisplayMode> {
        Binding(
            get: { coordinator.calViewMode },
            set: { coordinator.calViewMode = $0; coordinator.onCalModeChange?($0) }
        )
    }

    var body: some View {
        HStack(spacing: 12) {
            Button {
                coordinator.onCalPrev?()
            } label: {
                Image(systemName: "chevron.left")
                    .font(ToolbarMetrics.iconFont)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Previous")

            Text(coordinator.calHeaderDate)
                .font(ToolbarMetrics.titleFont)
                .foregroundStyle(.primary)
                .lineLimit(1)

            Button {
                coordinator.onCalNext?()
            } label: {
                Image(systemName: "chevron.right")
                    .font(ToolbarMetrics.iconFont)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Next")

            HStack(spacing: 0) {
                ForEach(CalendarViewDisplayMode.allCases, id: \.self) { mode in
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
                            modeBinding.wrappedValue = mode
                        }
                    } label: {
                        Text(mode.rawValue)
                            .font(ToolbarMetrics.font(coordinator.calViewMode == mode ? .semibold : .regular))
                            .foregroundStyle(
                                coordinator.calViewMode == mode
                                    ? AnyShapeStyle(.primary)
                                    : AnyShapeStyle(.secondary)
                            )
                            .padding(.horizontal, 14)
                            .padding(.vertical, 5)
                            .background(
                                coordinator.calViewMode == mode
                                    ? AnyShapeStyle(Color.accentColor.opacity(0.12))
                                    : AnyShapeStyle(Color.clear)
                            )
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(.thinMaterial)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(DesignSystem.Colors.chromeStroke, lineWidth: 0.8))
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

/// Trailing calendar toolbar control: right sidebar toggle (own `NSToolbarItem` for a stable edge anchor).
struct CalToolbarSidebarToggleView: View {
    var coordinator: AppToolbarCoordinator

    private func setSidebarPanel(_ panel: CalendarSidebarPanel) {
        coordinator.calSidebarPanel = panel
        coordinator.onCalSidebarPanelChange?(panel)
    }

    var body: some View {
        Button {
            coordinator.onCalSidebarToggle?()
        } label: {
            Image(systemName: "sidebar.right")
                .font(ToolbarMetrics.iconFont)
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(coordinator.calSidebarShown ? "Hide right sidebar (right-click to choose panel)" : "Show right sidebar (right-click to choose panel)")
        .contextMenu {
            Button {
                setSidebarPanel(.eventList)
            } label: {
                Label(
                    "Event List",
                    systemImage: coordinator.calSidebarPanel == .eventList ? "checkmark" : "list.bullet"
                )
            }

            Button {
                setSidebarPanel(.tasks)
            } label: {
                Label(
                    "Task List",
                    systemImage: coordinator.calSidebarPanel == .tasks ? "checkmark" : "checklist"
                )
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

/// Brightspace tab title row: fixed section label + portal-home control (web `document.title` is not shown here to avoid D2L "Loading…" flashes).
struct BsToolbarTitleView: View {
    var coordinator: AppToolbarCoordinator

    var body: some View {
        HStack(spacing: 8) {
            Text(String(localized: "app.page.brightspace"))
                .font(ToolbarMetrics.titleFont)
                .foregroundStyle(.primary)
                .lineLimit(1)
            Button {
                coordinator.onBsPortalHome?()
            } label: {
                Image(systemName: "arrow.counterclockwise.circle")
                    .font(ToolbarMetrics.font(.medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(String(localized: "brightspace.toolbar.portal_home_help"))
            .accessibilityLabel(String(localized: "brightspace.toolbar.portal_home_a11y"))
        }
        .fixedSize()
        .frame(maxWidth: 360, alignment: .center)
    }
}

/// Profile avatar circle button shared across Calendar and Brightspace toolbars.
struct ToolbarProfileAvatarView: View {
    var coordinator: AppToolbarCoordinator

    var body: some View {
        Button { coordinator.onNavigate?(.profile) } label: {
            Circle()
                .fill(Color.accentColor)
                .frame(width: 22, height: 22)
                .overlay {
                    if coordinator.profileInitials.isEmpty {
                        Image(systemName: "person.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.white)
                    } else {
                        Text(coordinator.profileInitials)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
        }
        .buttonStyle(.plain)
        .help(String(localized: "app.toolbar.open_profile_help"))
        .accessibilityLabel(String(localized: "app.toolbar.open_profile_a11y"))
        .accessibilityIdentifier("toolbar.profile")
    }
}


// MARK: - Academics Views

struct AcademicsToolbarSidebarToggleView: View {
    var coordinator: AppToolbarCoordinator

    var body: some View {
        Button {
            coordinator.onAcademicsSidebarToggle?()
        } label: {
            Image(systemName: "sidebar.left")
                .font(ToolbarMetrics.iconFont)
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(coordinator.academicsSidebarShown ? "Hide stats sidebar" : "Show stats sidebar")
    }
}

// MARK: - Safe Toggle Sidebar View

struct SafeSidebarToggleView: View {
    @State private var lastToggleTime = Date.distantPast
    var onToggleIntent: (() -> Void)? = nil

    var body: some View {
        Button {
            let now = Date()
            guard now.timeIntervalSince(lastToggleTime) > 0.4 else { return }
            lastToggleTime = now
            onToggleIntent?()
            NSApp.sendAction(#selector(NSSplitViewController.toggleSidebar(_:)), to: nil, from: nil)
        } label: {
            Image(systemName: "sidebar.left")
                .font(ToolbarMetrics.iconFont)
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .help("Toggle Sidebar")
    }
}
