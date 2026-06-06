// WebPortalSceneState.swift
// Feature: App / Toolbar
// Owner: ShortcutWebHostView, BrightspaceView

import Foundation
import Observation

/// Web portal feature scene state. Navigation actions flow through `ToolbarDispatcher`.
@Observable
@MainActor
final class WebPortalSceneState {
    var title: String = ""
    var canGoBack: Bool = false
    var canGoForward: Bool = false
    var isLoading: Bool = false

    var toolbarProjection: ToolbarProjection {
        ToolbarProjection(
            title: title,
            canGoBack: canGoBack,
            canGoForward: canGoForward,
            isLoading: isLoading
        )
    }

    struct ToolbarProjection: Equatable, Sendable {
        var title: String
        var canGoBack: Bool
        var canGoForward: Bool
        var isLoading: Bool
    }
}
