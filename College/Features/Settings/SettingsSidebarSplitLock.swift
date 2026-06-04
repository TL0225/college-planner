// SettingsSidebarSplitLock.swift
// Feature: Settings
// Purpose: Settings module — SettingsSidebarSplitLock.
// Data: CollegePersistence / repositories when applicable.

import AppKit
import SwiftUI

/// Keeps the Settings sidebar at a fixed width.
///
/// SwiftUI's `NavigationSplitView` is backed by `NSSplitViewController`, which owns the
/// underlying `NSSplitView`. Do not modify `NSSplitView.delegate` or call
/// `setHoldingPriority(_:forSubviewAt:)` on that split view — configure `NSSplitViewItem`
/// thickness instead (see Apple documentation for `NSSplitViewController`).
struct SettingsSidebarSplitLock: NSViewRepresentable {
    let sidebarWidth: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(sidebarWidth: sidebarWidth)
    }

    func makeNSView(context: Context) -> NSView {
        let view = SettingsSplitLockAnchorView()
        view.coordinator = context.coordinator
        context.coordinator.anchorView = view
        view.sidebarWidth = sidebarWidth
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.sidebarWidth = sidebarWidth
        guard let view = nsView as? SettingsSplitLockAnchorView else { return }
        view.sidebarWidth = sidebarWidth
        view.scheduleEnforce()
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.teardownObserver()
    }

    @MainActor
    final class Coordinator {
        var sidebarWidth: CGFloat
        fileprivate weak var anchorView: SettingsSplitLockAnchorView?
        private weak var observedSidebarSubview: NSView?
        private var frameObserver: NSObjectProtocol?

        init(sidebarWidth: CGFloat) {
            self.sidebarWidth = sidebarWidth
        }

        func teardownObserver() {
            if let frameObserver {
                NotificationCenter.default.removeObserver(frameObserver)
                self.frameObserver = nil
            }
            observedSidebarSubview = nil
        }

        func installFrameObserverIfNeeded(sidebarSubview: NSView) {
            guard observedSidebarSubview !== sidebarSubview else { return }
            teardownObserver()
            observedSidebarSubview = sidebarSubview
            frameObserver = NotificationCenter.default.addObserver(
                forName: NSView.frameDidChangeNotification,
                object: sidebarSubview,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.enforceFixedSidebarWidth()
                }
            }
        }

        func enforceFixedSidebarWidth() {
            anchorView?.scheduleEnforce()
        }
    }
}

private final class SettingsSplitLockAnchorView: NSView {
    weak var coordinator: SettingsSidebarSplitLock.Coordinator?
    var sidebarWidth: CGFloat = SettingsMetrics.sidebarWidth
    private var pendingEnforce = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        scheduleEnforce()
    }

    override func layout() {
        super.layout()
        scheduleEnforce()
    }

    func scheduleEnforce() {
        guard !pendingEnforce else { return }
        pendingEnforce = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.pendingEnforce = false
            self.applyFixedSidebarWidth()
        }
    }

    private func applyFixedSidebarWidth() {
        guard let coordinator else { return }

        if let splitController = findSplitViewController() {
            applyFixedWidth(to: splitController, width: sidebarWidth)
            if let sidebarSubview = splitController.splitView.subviews.first {
                coordinator.installFrameObserverIfNeeded(sidebarSubview: sidebarSubview)
            }
            return
        }

        // Fallback when only the raw split view is reachable (older OS layouts).
        guard let splitView = findEnclosingSplitView() ?? findSplitViewInWindow(),
              splitView.subviews.count >= 2
        else { return }

        let current = splitView.subviews[0].frame.width
        if abs(current - sidebarWidth) > 0.5 {
            splitView.setPosition(sidebarWidth, ofDividerAt: 0)
        }
        coordinator.installFrameObserverIfNeeded(sidebarSubview: splitView.subviews[0])
    }

    private func applyFixedWidth(to controller: NSSplitViewController, width: CGFloat) {
        guard let sidebarItem = controller.splitViewItems.first else { return }
        sidebarItem.minimumThickness = width
        sidebarItem.maximumThickness = width
        sidebarItem.canCollapse = false
    }

    private func findSplitViewController() -> NSSplitViewController? {
        var responder: NSResponder? = nextResponder
        while let next = responder {
            if let controller = next as? NSSplitViewController {
                return controller
            }
            responder = next.nextResponder
        }

        if let root = window?.contentViewController {
            return findSplitViewController(in: root)
        }
        return nil
    }

    private func findSplitViewController(in viewController: NSViewController) -> NSSplitViewController? {
        if let split = viewController as? NSSplitViewController {
            return split
        }
        for child in viewController.children {
            if let found = findSplitViewController(in: child) {
                return found
            }
        }
        return nil
    }

    private func findEnclosingSplitView() -> NSSplitView? {
        var current: NSView? = self
        while let view = current {
            if let split = view as? NSSplitView { return split }
            current = view.superview
        }
        return nil
    }

    private func findSplitViewInWindow() -> NSSplitView? {
        guard let root = window?.contentView else { return nil }
        return root.firstSubview(ofType: NSSplitView.self)
    }
}
