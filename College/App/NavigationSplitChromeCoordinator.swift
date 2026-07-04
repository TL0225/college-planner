// NavigationSplitChromeCoordinator.swift
// Feature: App
// Purpose: App module — NavigationSplitChromeCoordinator.
// Data: CollegePersistence / repositories when applicable.

import AppKit

// MARK: - Tahoe chrome audit matrix (Phase A)
//
// | Row | As-built | Target | Apple doc | Pass after remediation |
// |-----|----------|--------|-----------|------------------------|
// | Window chrome | `fullSizeContentView`, transparent titlebar via delegate + `WindowChromeSetter` | Same; timing via coordinator | Unified toolbar / full-size content (AppKit) | Pass |
// | Toolbar style | Scene `.windowToolbarStyle(.unified)` + delegate `toolbarStyle = .unified` | Scene owns style; delegate owns timing flags | UnifiedWindowToolbarStyle | Pass (documented split) |
// | Split visibility | Fixed icon-only sidebar; no toolbar toggle | No hide/resize | NavigationSplitView | Pass |
// | Bridge triggers | Bridge layout, delegate async, `activePage` | + fullscreen will/did enter/exit, resize on main window only | Lifecycle re-apply (engineering) | Pass |
// | Calendar 1px rules | Leading `Rectangle`, `Divider()`, card `chromeStroke` + `.thinMaterial` | Solid canvas + glass sidebars + spacing | Materials / spacing, not strokes | Pass (Phase C) |
// | Academics seams | Inspector chrome (out of Calendar scope) | No change this PR | — | N/A |
//
// Gemini tier 1–3: Accurate. `dividerColor = .clear`: not supported; subview hiding retained.
//
// Ownership: `CollegeApp` → unified toolbar style. `CollegeAppDelegate` → resizable-window chrome flags + coordinator.
// Settings uses separate `NSToolbar` — never passed to `scheduleReapply` (non-resizable / different window).

/// Central entry for post-mount NavigationSplitView divider neutralization.
@MainActor
enum NavigationSplitChromeCoordinator {
    private static var latePassTasks: [ObjectIdentifier: Task<Void, Never>] = [:]

    /// Applies chrome immediately when the window is eligible (resizable, non-sheet).
    static func applyToWindow(_ window: NSWindow?) {
        guard shouldApplyChrome(to: window) else { return }
        NavigationSplitChromeEngine.applyToWindow(window)
    }

    /// Immediate apply plus coalesced late pass (~100ms) for fullscreen resize transactions.
    static func scheduleReapply(to window: NSWindow?, debounce: TimeInterval = 0.1) {
        guard let window, shouldApplyChrome(to: window) else { return }

        applyToWindow(window)

        let key = ObjectIdentifier(window)
        latePassTasks[key]?.cancel()

        latePassTasks[key] = Task { @MainActor in
            let nanos = UInt64(max(0, debounce) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanos)
            guard !Task.isCancelled else { return }
            applyToWindow(window)
        }
    }

    static func shouldApplyChrome(to window: NSWindow?) -> Bool {
        guard let window else { return false }
        guard window.styleMask.contains(.resizable), !window.isSheet else { return false }
        return true
    }

    /// Notification handlers: only the main content window (not Settings / sheets).
    static func handleNotification(_ notification: Notification, targetMainWindow: NSWindow?) {
        guard let window = notification.object as? NSWindow else { return }
        guard let targetMainWindow, window === targetMainWindow else { return }
        scheduleReapply(to: window)
    }
}

// MARK: - AppKit view-tree engine (private)

@MainActor
private enum NavigationSplitChromeEngine {
    static func applyTransparentDividers(to splitView: NSSplitView) {
        neutralizeDividerViews(in: splitView)
    }

    static func applyToWindow(_ window: NSWindow?) {
        guard let root = window?.contentView else { return }

        for splitView in root.allSubviews(ofType: NSSplitView.self) {
            applyTransparentDividers(to: splitView)
        }

        _ = MainSidebarSplitAutosave.applyTrafficLightCenteredWidthIfNeeded(in: window)
        neutralizeThinRules(in: root, ancestors: [], scope: .all)
        neutralizeToolbarButtonGlass(in: window)
    }

    /// Strips Liquid Glass platters from toolbar icon buttons (search, overflow, sidebar toggle)
    /// so only the glyphs remain. AppKit recreates these controls on resize; re-run on every reapply.
    static func neutralizeToolbarButtonGlass(in window: NSWindow?) {
        guard let window else { return }
        guard let root = window.contentView?.superview ?? window.contentView else { return }

        for view in root.allSubviews(ofType: NSView.self) {
            guard let button = view as? NSButton else { continue }
            guard isToolbarRegionButton(button, in: window) else { continue }
            guard button.isBordered else { continue }
            button.isBordered = false
        }
    }

    private static func isToolbarRegionButton(_ view: NSView, in window: NSWindow) -> Bool {
        var current: NSView? = view
        while let node = current {
            let name = String(describing: type(of: node))
            if name.contains("ClippedItemsIndicator") || name.contains("OverflowItem") {
                return true
            }
            if name.contains("Toolbar") || name.contains("Titlebar") || name.contains("NSToolbar") {
                return true
            }
            if node === window.contentView {
                break
            }
            current = node.superview
        }
        return false
    }

    /// Strips the Liquid Glass "platter" behind the toolbar's overflow ("»") indicator so
    /// only the chevron glyph remains, matching the app's otherwise borderless toolbar items.
    ///
    /// The overflow control is the private `NSToolbarClippedItemsIndicator`, an `NSButton`
    /// that AppKit inserts at the trailing edge when items don't fit. Apple's supported way to
    /// drop a toolbar item's glass is `isBordered = false` (WWDC25 — "Build an AppKit app with
    /// the new design"), which applies to this button too. The indicator is recreated as the
    /// window resizes, so this re-runs on every chrome reapply (mount / resize / fullscreen).
    static func neutralizeToolbarOverflowGlass(in window: NSWindow?) {
        neutralizeToolbarButtonGlass(in: window)
    }

    private enum RuleScope {
        case toolbarOnly
        case all
    }

    private static func neutralizeDividerViews(in view: NSView) {
        let typeName = String(describing: type(of: view))
        let isKnownDividerType = typeName.localizedCaseInsensitiveContains("divider")
            || typeName.localizedCaseInsensitiveContains("splitter")
            || typeName.localizedCaseInsensitiveContains("separator")

        let size = view.bounds.size
        let isThinVerticalRule = size.width > 0 && size.width <= 4 && size.height >= 24
        let parentIsSplit = view.superview is NSSplitView

        // A real split divider is a leaf rule. A *column* (sidebar/detail) is a
        // container that hosts SwiftUI content. Toggling the sidebar animates its
        // hosting column through thin widths (1–4px); without this guard the thin
        // heuristic would match that column mid-animation and permanently hide it
        // (`isHidden` is never reset), so the sidebar never reappears.
        if isKnownDividerType {
            hideAsTransparentRule(view)
        } else if parentIsSplit && isThinVerticalRule && view.subviews.isEmpty && !isColumnContainer(typeName) {
            hideAsTransparentRule(view)
        }

        for subview in view.subviews {
            neutralizeDividerViews(in: subview)
        }
    }

    /// True for view classes that host column content (and must never be hidden
    /// by the thin-rule heuristic), even if momentarily measured as a thin strip.
    private static func isColumnContainer(_ typeName: String) -> Bool {
        typeName.contains("Hosting")
            || typeName.contains("ScrollView")
            || typeName.contains("ClipView")
            || typeName.contains("Stack")
            || typeName.contains("SplitView")
    }

    private static func neutralizeThinRules(in view: NSView, ancestors: [NSView], scope: RuleScope) {
        let chain = ancestors + [view]
        let inToolbar = isToolbarOrTitlebarRegion(chain)

        if scope == .toolbarOnly, inToolbar {
            maybeHideThinRule(view)
        } else if scope == .all, !inToolbar {
            maybeHideContentColumnRule(view)
        }

        for subview in view.subviews {
            neutralizeThinRules(in: subview, ancestors: chain, scope: scope)
        }
    }

    private static func maybeHideThinRule(_ view: NSView) {
        let size = view.bounds.size
        let isThinVerticalRule = size.width > 0 && size.width <= 2 && size.height >= 18
        let isThinHorizontalRule = size.height > 0 && size.height <= 2 && size.width >= 18
        guard isThinVerticalRule || isThinHorizontalRule else { return }
        hideAsTransparentRule(view)
    }

    private static func maybeHideContentColumnRule(_ view: NSView) {
        let size = view.bounds.size
        guard size.width > 0, size.width <= 4, size.height >= 80 else { return }
        guard view.subviews.isEmpty || view is NSBox else { return }

        let typeName = String(describing: type(of: view))
        if typeName.contains("ScrollView") || typeName.contains("Hosting") { return }

        hideAsTransparentRule(view)
    }

    private static func hideAsTransparentRule(_ view: NSView) {
        view.alphaValue = 0
        view.isHidden = true
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        view.layer?.borderWidth = 0
    }

    private static func isToolbarOrTitlebarRegion(_ chain: [NSView]) -> Bool {
        chain.contains { view in
            let name = String(describing: type(of: view))
            return name.contains("Toolbar")
                || name.contains("Titlebar")
                || name.contains("NSTitlebar")
                || name.contains("NSToolbar")
        }
    }
}

/// Backward-compatible alias for call sites migrating to the coordinator.
@MainActor
enum NavigationSplitChrome {
    static func applyToWindow(_ window: NSWindow?) {
        NavigationSplitChromeCoordinator.applyToWindow(window)
    }

    static func applyTransparentDividers(to splitView: NSSplitView) {
        NavigationSplitChromeEngine.applyTransparentDividers(to: splitView)
    }
}
