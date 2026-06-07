// CalendarToolbarContent.swift
// Feature: App / Toolbar

import CollegeCalendar
import SwiftUI

struct CalendarToolbarContent: ToolbarContent {
    let dispatcher: ToolbarDispatcher
    let calendarScene: CalendarSceneState

    var body: some ToolbarContent {
        ToolbarItem(id: "cal.chrome", placement: .principal) {
            CalToolbarChromeView(dispatcher: dispatcher, calendarScene: calendarScene)
        }
        .sharedBackgroundVisibility(.hidden)
        ToolbarItem(id: "cal.sidebarToggle", placement: .primaryAction) {
            CalToolbarSidebarToggleView(dispatcher: dispatcher, calendarScene: calendarScene)
        }
        .sharedBackgroundVisibility(.hidden)
    }
}
