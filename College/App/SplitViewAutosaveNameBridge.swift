// SplitViewAutosaveNameBridge.swift
// Feature: App
// Purpose: App module — SplitViewAutosaveNameBridge.
// Data: CollegePersistence / repositories when applicable.

import AppKit
import SwiftUI

/// Applies autosave naming and transparent split/toolbar column chrome for the main `NavigationSplitView`.
struct SplitViewAutosaveNameBridge: NSViewRepresentable {
    let autosaveName: String

    func makeNSView(context: Context) -> NSView {
        let view = SplitViewAutosaveNameView()
        view.autosaveName = autosaveName
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? SplitViewAutosaveNameView else { return }
        view.autosaveName = autosaveName
        view.applyChromeIfPossible()
    }

    private final class SplitViewAutosaveNameView: NSView {
        var autosaveName: String = ""

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            applyChromeIfPossible()
        }

        override func layout() {
            super.layout()
            // Defer chrome work so we never call into subview property setters
            // (isHidden, wantsLayer, etc.) while the layout pass is still running —
            // that would re-invalidate layout and trigger the "layoutSubtreeIfNeeded
            // on a view which is already being laid out" AppKit warning.
            DispatchQueue.main.async { [weak self] in
                self?.applyChromeIfPossible()
            }
        }

        func applyChromeIfPossible() {
            guard !autosaveName.isEmpty else { return }

            if let splitView = findEnclosingSplitView() ?? findSplitViewInWindow() {
                if splitView.autosaveName != autosaveName {
                    splitView.autosaveName = autosaveName
                }
                NavigationSplitChrome.applyTransparentDividers(to: splitView)
            }

            NavigationSplitChromeCoordinator.scheduleReapply(to: window)
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
