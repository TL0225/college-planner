// CalendarSceneState.swift
// Feature: App / Toolbar
// Owner: CalendarView — College/Features/Calendar/CalendarView.swift

import Foundation
import Observation

/// Calendar feature scene state. Toolbar reads `toolbarProjection`; business truth lives here.
@Observable
@MainActor
final class CalendarSceneState {
    // MARK: - Feature truth
    var headerDate: String = ""
    var viewMode: CalendarViewDisplayMode = .month
    var sidebarShown: Bool = true
    var sidebarPanel: CalendarSidebarPanel = .eventList
    var profileInitials: String = ""
    var toolbarSearchText: String = ""
    var toolbarSearchResults: [CalendarToolbarSearchMatch] = []
    var toolbarSearchExpanded: Bool = false

    // MARK: - Toolbar projection
    var toolbarProjection: ToolbarProjection {
        ToolbarProjection(
            headerDate: headerDate,
            viewMode: viewMode,
            sidebarShown: sidebarShown,
            sidebarPanel: sidebarPanel
        )
    }

    struct ToolbarProjection: Equatable, Sendable {
        var headerDate: String
        var viewMode: CalendarViewDisplayMode
        var sidebarShown: Bool
        var sidebarPanel: CalendarSidebarPanel
    }
}
