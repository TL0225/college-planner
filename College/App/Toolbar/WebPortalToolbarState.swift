// WebPortalToolbarState.swift
// Feature: App
// Purpose: App module — WebPortalToolbarState.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import Observation

/// Brightspace / web shortcut toolbar state and actions (owned by each web host view).
@Observable
@MainActor
final class WebPortalToolbarState {
    var title: String = ""
    var canGoBack: Bool = false
    var canGoForward: Bool = false
    var isLoading: Bool = false

    var onBack: (() -> Void)?
    var onForward: (() -> Void)?
    var onReload: (() -> Void)?
    var onPortalHome: (() -> Void)?
    var onFind: (() -> Void)?

    func back() { onBack?() }
    func forward() { onForward?() }
    func reload() { onReload?() }
    func portalHome() { onPortalHome?() }
    func findInPage() { onFind?() }

    func clearHandlers() {
        onBack = nil
        onForward = nil
        onReload = nil
        onPortalHome = nil
        onFind = nil
    }
}
