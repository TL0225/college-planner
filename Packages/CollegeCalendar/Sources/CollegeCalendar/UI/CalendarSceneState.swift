// CalendarSceneState.swift
// Feature: Calendar
// Owner: CalendarView — Packages/CollegeCalendar

import Foundation
import Observation

/// Calendar feature scene state. Toolbar reads `toolbarProjection`; business truth lives here.
@Observable
@MainActor
public final class CalendarSceneState {
    public var headerDate: String = ""
    public var viewMode: CalendarViewDisplayMode = .month
    public var sidebarShown: Bool = true
    public var sidebarPanel: CalendarSidebarPanel = .eventList
    public var profileInitials: String = ""
    public var toolbarSearchText: String = ""
    public var toolbarSearchResults: [CalendarToolbarSearchMatch] = []
    public var toolbarSearchExpanded: Bool = false

    /// Live handler installed by `CalendarView` while mounted (avoids stale struct captures in `ToolbarDispatcher`).
    public var toolbarHandler: (@MainActor (CalendarToolbarAction) -> Void)?

    public init() {}

    public var toolbarProjection: ToolbarProjection {
        ToolbarProjection(
            headerDate: headerDate,
            viewMode: viewMode,
            sidebarShown: sidebarShown,
            sidebarPanel: sidebarPanel
        )
    }

    public struct ToolbarProjection: Equatable {
        public var headerDate: String
        public var viewMode: CalendarViewDisplayMode
        public var sidebarShown: Bool
        public var sidebarPanel: CalendarSidebarPanel

        public init(
            headerDate: String,
            viewMode: CalendarViewDisplayMode,
            sidebarShown: Bool,
            sidebarPanel: CalendarSidebarPanel
        ) {
            self.headerDate = headerDate
            self.viewMode = viewMode
            self.sidebarShown = sidebarShown
            self.sidebarPanel = sidebarPanel
        }
    }
}
