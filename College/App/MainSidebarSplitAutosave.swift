// MainSidebarSplitAutosave.swift
// Feature: App
// Purpose: Lock the main NavigationSplitView sidebar to a fixed icon-only width.

import AppKit
import Foundation

/// The main shell sidebar uses a fixed width (icon-only rail). SwiftUI owns the
/// underlying `NSSplitView` via `NSSplitViewController`, so divider locking must go
/// through `splitViewItems` — never `NSSplitView.setHoldingPriority`.
@MainActor
enum MainSidebarSplitAutosave {
    static let autosaveName = AutosaveNames.mainSidebarSplit
    static let columnWidthDidResolveNotification = Notification.Name("MainSidebarSplitAutosave.columnWidthDidResolve")

    static var fixedLeadingColumnWidth: CGFloat { SidebarColumnLayout.fixedWidth }

    private static var appliedSplitViewKeys = Set<ObjectIdentifier>()
    private static var appliedLeadingColumnWidths: [ObjectIdentifier: CGFloat] = [:]
    private static var lastPostedColumnWidth: CGFloat?

    /// Always returns the fixed shell sidebar width (legacy call sites).
    static func restoredLeadingColumnWidth(default defaultWidth: CGFloat = SidebarColumnLayout.fixedWidth) -> CGFloat {
        fixedLeadingColumnWidth
    }

    /// Width for the main shell sidebar: traffic-light-centered when a window is available.
    static func resolvedLeadingColumnWidth(in window: NSWindow?) -> CGFloat {
        guard let window else { return fixedLeadingColumnWidth }
        return SidebarColumnLayout.trafficLightCenteredWidth(in: window)
    }

    /// Clears AppKit autosave and applies the fixed divider position once per split view.
    static func applyFixedPositionIfNeeded(to splitView: NSSplitView) {
        applyFixedPosition(to: splitView, width: resolvedLeadingColumnWidth(in: splitView.window))
    }

    /// Pins the leading column to `width`, re-applying when the traffic-light-centered width changes.
    static func applyFixedPosition(to splitView: NSSplitView, width: CGFloat) {
        guard splitView.isVertical, splitView.subviews.count >= 2 else { return }

        let key = ObjectIdentifier(splitView)
        if !appliedSplitViewKeys.contains(key) {
            appliedSplitViewKeys.insert(key)
            splitView.autosaveName = ""
            lockDividerResizing(in: splitView)
        }

        if let lastWidth = appliedLeadingColumnWidths[key], abs(lastWidth - width) <= 0.5 {
            return
        }
        appliedLeadingColumnWidths[key] = width
        splitView.setPosition(width, ofDividerAt: 0)
        postColumnWidthIfNeeded(width)
    }

    private static func postColumnWidthIfNeeded(_ width: CGFloat) {
        guard lastPostedColumnWidth.map({ abs($0 - width) > 0.5 }) ?? true else { return }
        lastPostedColumnWidth = width
        NotificationCenter.default.post(
            name: columnWidthDidResolveNotification,
            object: nil,
            userInfo: ["width": width]
        )
    }

    /// Prevents user-driven divider drags; the detail column absorbs window resize.
    /// SwiftUI's `NavigationSplitView` owns the split view through `NSSplitViewController` —
    /// holding priorities must be set on `splitViewItems`, not via `NSSplitView.setHoldingPriority`.
    private static func lockDividerResizing(in splitView: NSSplitView) {
        guard let controller = splitViewController(for: splitView) else { return }
        let items = controller.splitViewItems
        guard !items.isEmpty else { return }
        items[0].holdingPriority = .init(1000)
        if items.count > 1 {
            items[1].holdingPriority = .init(250)
        }
    }

    private static func splitViewController(for splitView: NSSplitView) -> NSSplitViewController? {
        if let controller = splitView.delegate as? NSSplitViewController {
            return controller
        }
        var responder: NSResponder? = splitView.nextResponder
        while let current = responder {
            if let controller = current as? NSSplitViewController {
                return controller
            }
            responder = current.nextResponder
        }
        return nil
    }

    @MainActor
    static func applyTrafficLightCenteredWidthIfNeeded(in window: NSWindow?) -> CGFloat {
        guard let window else { return fixedLeadingColumnWidth }
        guard let root = window.contentView else { return fixedLeadingColumnWidth }
        let width = SidebarColumnLayout.trafficLightCenteredWidth(in: window)
        for splitView in root.allSubviews(ofType: NSSplitView.self) {
            applyFixedPosition(to: splitView, width: width)
        }
        return width
    }
}
