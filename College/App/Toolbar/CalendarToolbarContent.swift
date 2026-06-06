// CalendarToolbarContent.swift
// Feature: App / Toolbar

import SwiftUI

struct CalendarToolbarContent: ToolbarContent {
    var body: some ToolbarContent {
        ToolbarItem(id: "cal.chrome", placement: .principal) {
            CalToolbarChromeView()
        }
        ToolbarItem(id: "cal.sidebarToggle", placement: .primaryAction) {
            CalToolbarSidebarToggleView()
        }
    }
}
