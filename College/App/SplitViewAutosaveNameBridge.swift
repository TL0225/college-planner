// SplitViewAutosaveNameBridge.swift
// Feature: App
// Purpose: App module — SplitViewAutosaveNameBridge.
// Data: CollegePersistence / repositories when applicable.

import AppKit
import SwiftUI

/// Applies autosave naming and transparent split/toolbar column chrome for the main `NavigationSplitView`.
struct SplitViewAutosaveNameBridge: NSViewRepresentable {
    let autosaveName: String
    @Binding var resolvedColumnWidth: CGFloat

    func makeNSView(context: Context) -> NSView {
        let view = SplitViewAutosaveNameView()
        view.autosaveName = autosaveName
        view.onResolvedColumnWidth = { width in
            guard abs(resolvedColumnWidth - width) > 0.5 else { return }
            resolvedColumnWidth = width
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? SplitViewAutosaveNameView else { return }
        view.autosaveName = autosaveName
        view.onResolvedColumnWidth = { width in
            guard abs(resolvedColumnWidth - width) > 0.5 else { return }
            resolvedColumnWidth = width
        }
        view.applyChromeIfPossible()
    }

    private final class SplitViewAutosaveNameView: NSView {
        var autosaveName: String = ""
        var onResolvedColumnWidth: ((CGFloat) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            applyChromeIfPossible()
        }

        func applyChromeIfPossible() {
            applySplitDividerChromeIfPossible()
            NavigationSplitChromeCoordinator.scheduleReapply(to: window)
        }

        override func layout() {
            super.layout()
            // Divider neutralization only — avoid re-pinning sidebar width every layout pass.
            DispatchQueue.main.async { [weak self] in
                guard let self, let splitView = self.findEnclosingSplitView() ?? self.findSplitViewInWindow() else { return }
                NavigationSplitChrome.applyTransparentDividers(to: splitView)
                self.reapplyFixedSidebarWidthIfDrifted(on: splitView)
            }
        }

        private func reapplyFixedSidebarWidthIfDrifted(on splitView: NSSplitView) {
            guard autosaveName == MainSidebarSplitAutosave.autosaveName else { return }
            guard splitView.isVertical, let leadingColumn = splitView.subviews.first else { return }
            let target = MainSidebarSplitAutosave.resolvedLeadingColumnWidth(in: window)
            guard abs(leadingColumn.frame.width - target) > 1 else { return }
            MainSidebarSplitAutosave.applyFixedPosition(to: splitView, width: target)
        }

        private func applySplitDividerChromeIfPossible() {
            guard !autosaveName.isEmpty else { return }

            if let splitView = findEnclosingSplitView() ?? findSplitViewInWindow() {
                if autosaveName == MainSidebarSplitAutosave.autosaveName {
                    MainActor.assumeIsolated {
                        MainSidebarSplitAutosave.applyFixedPositionIfNeeded(to: splitView)
                        let width = MainSidebarSplitAutosave.resolvedLeadingColumnWidth(in: window)
                        onResolvedColumnWidth?(width)
                    }
                } else if splitView.autosaveName != autosaveName {
                    splitView.autosaveName = autosaveName
                }
                NavigationSplitChrome.applyTransparentDividers(to: splitView)
            }
        }

        private func findEnclosingSplitView() -> NSSplitView? {
            var current: NSView? = self
            while let view = current {
                if let split = view as? NSSplitView {
                    return split
                }
                current = view.superview
            }
            return nil
        }

        private func findSplitViewInWindow() -> NSSplitView? {
            guard let root = window?.contentView else { return nil }
            return root.firstSubview(ofType: NSSplitView.self)
        }
    }
}

extension NSView {
    func firstSubview<T: NSView>(ofType type: T.Type) -> T? {
        allSubviews(ofType: type).first
    }

    func allSubviews<T: NSView>(ofType type: T.Type) -> [T] {
        var results: [T] = []
        if let match = self as? T {
            results.append(match)
        }
        for subview in subviews {
            results.append(contentsOf: subview.allSubviews(ofType: type))
        }
        return results
    }
}
